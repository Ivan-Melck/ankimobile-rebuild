#!/usr/bin/env python3
"""Compare the original desktop fork with the shipping Swift collection path."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import math
import os
from pathlib import Path
import select
import shutil
import socket
import subprocess
import tempfile
import time
from isolation import environment_and_command

ROOT = Path(__file__).resolve().parents[2]
FORK = ROOT / "Vendor/anki"
MODELS = {"legacy": "RWKV_trained_on_5000_10000.bin", "sm36": "sm36/weights.f32.bin", "sm40": "sm40v2/weights.f32.bin", "sm55": "sm55/weights.f32.bin", "sm56": "sm56/weights.f32.bin"}


class Peer:
    def __init__(self, command, env, directory, name, clock_library):
        self.log = (directory / f"{name}.log").open("w")
        env, command = environment_and_command(command, env, ROOT, directory, clock_library, name)
        self.process = subprocess.Popen(command, cwd=ROOT, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.log, text=True, bufsize=1)

    def call(self, op, **kwargs):
        self.process.stdin.write(json.dumps({"op": op, **kwargs}) + "\n")
        self.process.stdin.flush()
        if not select.select([self.process.stdout], [], [], 120)[0]:
            raise RuntimeError(f"Comparison peer timed out during {op}")
        line = self.process.stdout.readline()
        if not line: raise RuntimeError(f"Comparison peer exited during {op}; exit={self.process.poll()}")
        result = json.loads(line)
        if "error" in result: raise RuntimeError(f"{op}: {result['error']}")
        return result["result"]

    def close(self):
        self.process.terminate()
        try: self.process.wait(timeout=10)
        except subprocess.TimeoutExpired: self.process.kill(); self.process.wait()
        self.log.close()


def set_clock(path, millis):
    temporary = path.with_suffix(".next")
    temporary.write_text(str(millis)); temporary.replace(path)


def differences(a, b, path="$", tolerance=1e-5):
    if type(a) is dict and type(b) is dict:
        result = []
        for key in sorted(a.keys() | b.keys()):
            if key not in a or key not in b: result.append({"path": path + "." + key, "reason": "missing field"})
            else: result.extend(differences(a[key], b[key], path + "." + key, tolerance))
        return result
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b): return [{"path": path, "reason": "length", "reference": len(a), "app": len(b)}]
        return [item for i, (x,y) in enumerate(zip(a,b)) for item in differences(x,y,f"{path}[{i}]",tolerance)]
    if isinstance(a, (int,float)) and isinstance(b, (int,float)):
        equal = a == b if isinstance(a,int) and isinstance(b,int) else math.isclose(a,b,rel_tol=tolerance,abs_tol=tolerance)
    else: equal = a == b
    if equal: return []
    # Synthetic scalar observations only. Personal text is never included.
    return [{"path": path, "reason": "value", "reference": a, "app": b}]


def compare_case(args, model, precision, mode, scenario):
    work = Path(tempfile.mkdtemp(prefix="anki-rwkv-compare-", dir=args.work))
    clock = work / "clock"; set_clock(clock, 1793016000000)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", TZ="UTC", ANKI_COMPARISON_CLOCK_FILE=str(clock), LD_PRELOAD=str(args.clock_library), PYTHONPATH=os.pathsep.join(str(FORK/p) for p in ("pylib","out/pylib","qt","out/qt")))
    env["RAYON_NUM_THREADS"]="1"
    probe=socket.socket(); probe.bind(("127.0.0.1",0)); probe.listen()
    env["ANKI_COMPARISON_PROBE_PORT"]=str(probe.getsockname()[1])
    reference = Peer([str(FORK/"out/pyenv/bin/python"), str(ROOT/"tools/comparison/reference.py")], env, work, "reference", args.clock_library)
    app = Peer([str(args.app)], env, work, "app", args.clock_library)
    result = {"model": model, "precision": precision, "mode": mode, "scenario": scenario, "steps": 0, "answers":0, "comparisons": 0, "mismatches": [], "work": str(work)}
    try:
        assert reference.call("clock") == app.call("clock") == "1793016000000", "Clocks are not controlled"
        isolation=reference.call("isolation")
        assert not isolation["liveCollectionVisible"] and isolation["installedLauncherHidden"]
        assert isolation["rsbridge"].startswith(str(FORK)), "Reference imported the installed Anki binding"
        result["isolation"]={name:json.loads((work/f"{name}-isolation.json").read_text()) for name in ("reference","app")}
        metadata = reference.call("seed", directory=str(work/"seed"), mode=mode,
            mixed=scenario in ("mixed","dynamic-replay"), dynamic_replay=scenario=="dynamic-replay",
            refresh=3 if scenario=="refresh" else 1, dynamic=scenario in ("dynamic-dr","dynamic-dr-fsrs7"),
            grade_order=scenario!="grade-order-off",fsrs={"fsrs4":3,"fsrs5":2,"fsrs7":0,"dynamic-dr-fsrs7":0}.get(scenario,1))
        for side in ("reference", "app"): shutil.copytree(work/"seed",work/side)
        weights = FORK/"qt/aqt/rwkv_inference"/MODELS[model]
        reference.call("open",directory=str(work/"reference"),model=model,precision=precision,weights=str(weights))
        app.call("open",directory=str(work/"app"))
        millis = metadata["now"]*1000
        for step in range(args.steps):
            if step == 6:
                if scenario in ("undo", "redo"):
                    reference.call("undo");app.call("undo")
                    if scenario == "redo":
                        reference.call("redo");app.call("redo")
                if scenario in ("reopen", "rollover"):
                    reference.call("close");app.call("close")
                    if scenario == "rollover":
                        millis+=86400000;set_clock(clock,millis)
                    reference.call("open",directory=str(work/"reference"),model=model,precision=precision,weights=str(weights))
                    app.call("open",directory=str(work/"app"))
            ref = reference.call("prepare",deckId=metadata["deckId"])
            actual = app.call("prepare",deckId=metadata["deckId"],model=model,precision=precision)
            if scenario=="dynamic-dr-fsrs7" and any(card.get("states",{}).get("dynamicDesiredRetentionEnabled") for card in ref.get("cards",[])):
                result["activeDynamicRetentionObserved"]=True
            with (work/"observations.jsonl").open("a") as trace:
                trace.write(json.dumps({"step":step,"clock":millis,"reference":ref,"app":actual})+"\n")
            result["steps"] += 1
            observed = {}
            for side, queue in (("reference",ref),("app",actual)):
                cards=queue.get("cards",[])
                observed[side]={"cardId":cards[0]["card"]["id"] if cards else None,
                    "counts":{key:queue.get(key,0) for key in ("newCount","learningCount","reviewCount")}}
                if cards:
                    observed[side]["input"]=queue.get("comparisonInput") if side=="reference" else cards[0].get("rwkvPrediction",{}).get("comparisonInput")
                    observed[side]["states"]=cards[0]["states"]
                    observed[side]["retrievability"]=cards[0].get("rwkvPrediction",{}).get("retrievability")
                    if side == "reference":
                        prediction=queue.get("fullPrediction") or {}
                        observed[side]["heads"]={key:prediction.get(source) for key,source in
                            (("buttonProbabilities","button_probabilities"),("curveRetrievability","curve_retrievability"),("currentInterval","current_interval"),("currentS90","current_s90"))}
                        for key,source in (("intervals","interval_overrides"),("s90s","s90_overrides")):
                            observed[side]["heads"][key]=[prediction.get(source,{}).get(grade) for grade in ("again","hard","good","easy")]
                    else:
                        prediction=cards[0].get("rwkvPrediction",{})
                        observed[side]["heads"]={key:prediction.get(key) for key in ("buttonProbabilities","curveRetrievability","currentInterval","currentS90","intervals","s90s")}
            delta=differences(observed["reference"],observed["app"],f"step[{step}].review")
            result["comparisons"] += 1
            before_ref=reference.call("inspect");before_app=app.call("inspect")
            delta += differences(before_ref,before_app,f"step[{step}].snapshot")
            result["comparisons"] += 1
            queues={side:peer.call("queue") for side,peer in (("reference",reference),("app",app))}
            orders={side:[(card["card"]["id"],card.get("queue")) for card in queue.get("cards",[])] for side,queue in queues.items()}
            delta+=differences(orders["reference"],orders["app"],f"step[{step}].queueOrder")
            result["comparisons"]+=1
            scores={side:peer.call("queueScores",cards=metadata["cards"]) for side,peer in (("reference",reference),("app",app))}
            delta+=differences(scores["reference"],scores["app"],f"step[{step}].queueScores")
            result["comparisons"]+=1
            if delta:
                result["mismatches"].extend(delta[:30]); break
            if not actual.get("cards"):
                if step==0:raise RuntimeError("Seed unexpectedly produced an empty review session")
                break
            seconds=[2.5,4.25,1.75,6.0][step%4]
            # Whole-second event times avoid differing Python/Foundation
            # float-to-millisecond truncation at quarter-second boundaries.
            # Explicit measured durations still include subsecond values.
            millis+=math.ceil(seconds)*1000;set_clock(clock,millis)
            rating=[1,2,3,4,3,4,2,3][step%8]
            reference.call("answer",rating=rating,seconds=seconds)
            app.call("answer",rating=rating,seconds=seconds)
            result["answers"]+=1
            # Recurrent replay happens on the mobile's next prepare. Persistent
            # collection state must already match immediately after the answer.
            delta=differences(reference.call("inspect")["tables"],app.call("inspect")["tables"],f"step[{step}].answeredTables")
            result["comparisons"]+=1
            if delta:
                result["mismatches"].extend(delta[:30]);break
        if scenario=="dynamic-dr-fsrs7" and not result.get("activeDynamicRetentionObserved"):
            raise RuntimeError("Dynamic-retention fixture did not activate per-grade retention")
        reference.call("close");app.call("close")
    except Exception as error:
        result["error"]=str(error)
    finally:
        reference.close();app.close()
        probe.close()
    result["status"]="error" if "error" in result else "mismatch" if result["mismatches"] else "match"
    if result["status"]=="match" and not args.keep:
        shutil.rmtree(work);result.pop("work")
    return result


def main():
    os.umask(0o077)
    parser=argparse.ArgumentParser()
    parser.add_argument("--models",nargs="+",choices=list(MODELS),default=list(MODELS))
    parser.add_argument("--precisions",nargs="+",choices=["f32","int8","int4","cards_int4_notes_int8"],default=["f32","int8","int4","cards_int4_notes_int8"])
    parser.add_argument("--modes",nargs="+",choices=["instant","curve","both"],default=["instant","curve","both"])
    parser.add_argument("--scenarios",nargs="+",choices=["standard","mixed","refresh","undo","redo","reopen","rollover","fsrs4","fsrs5","fsrs7","dynamic-dr","dynamic-dr-fsrs7","dynamic-replay","grade-order-off"],default=["standard","mixed","refresh","undo","redo","reopen","rollover"])
    parser.add_argument("--steps",type=int,default=24)
    parser.add_argument("--app",type=Path,default=ROOT/".build/debug/AnkiComparisonDriver")
    parser.add_argument("--clock-library",type=Path,default=Path("/tmp/anki-comparison-clock.so"))
    parser.add_argument("--work",type=Path,default=Path(tempfile.gettempdir()))
    parser.add_argument("--output",type=Path,default=Path("/tmp/anki-rwkv-comparison.json"))
    parser.add_argument("--keep",action="store_true")
    parser.add_argument("--jobs",type=int,default=4,help="independent synthetic cases to run concurrently")
    parser.add_argument("--offline",action="store_true",help="skip checking GitHub main; report the reference pin as unverified for freshness")
    args=parser.parse_args()
    if args.steps < 1:parser.error("--steps must be positive")
    if args.jobs < 1:parser.error("--jobs must be positive")
    subprocess.run(["git","-C",str(FORK),"diff","--exit-code","--quiet"],check=True)
    revision=subprocess.check_output(["git","-C",str(FORK),"rev-parse","HEAD"],text=True).strip()
    latest=None if args.offline else subprocess.check_output(["git","-C",str(FORK),"ls-remote","origin","refs/heads/main"],text=True,timeout=30).split()[0]
    if latest is not None and latest != revision:
        raise SystemExit("The pinned reference is behind fork main; update and rebuild before comparing.")
    manifest={"fork":revision,"latestMain":latest,"checkedAtUTC":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()),
              "isolationRequired":True,"appExecutableSHA256":hashlib.sha256(args.app.read_bytes()).hexdigest(),
              "models":{model:hashlib.sha256((FORK/"qt/aqt/rwkv_inference"/MODELS[model]).read_bytes()).hexdigest() for model in args.models}}
    cases=[]
    for model in args.models:
        original=FORK/"qt/aqt/rwkv_inference"/MODELS[model]
        assert hashlib.sha256(original.read_bytes()).digest()==hashlib.sha256((ROOT/f"Sources/FlashcardsCore/Resources/RWKV/{model}.bin").read_bytes()).digest()
        for precision in args.precisions:
            for mode in args.modes:
                for scenario in args.scenarios:
                    cases.append((model,precision,mode,scenario))
    results=[]
    with ThreadPoolExecutor(max_workers=args.jobs) as executor:
        futures={executor.submit(compare_case,args,*case):case for case in cases}
        for future in as_completed(futures):
            result=future.result();results.append(result)
            print(json.dumps(result),flush=True)
            temporary=args.output.with_suffix(".next")
            temporary.write_text(json.dumps({**manifest,"plannedCases":len(cases),"results":results},indent=2)+"\n")
            temporary.replace(args.output)
    return int(any(r["status"]!="match" for r in results))


if __name__=="__main__":raise SystemExit(main())
