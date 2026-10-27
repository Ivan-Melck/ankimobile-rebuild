#!/usr/bin/env python3
"""Produce a public report without temporary paths or process logs."""
import argparse
from collections import Counter
import json
from pathlib import Path
import subprocess

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("input",type=Path)
parser.add_argument("output",type=Path)
args=parser.parse_args()
report=json.loads(args.input.read_text())
results=report["results"]
if len(results)!=report["plannedCases"]:
    raise SystemExit("The matrix is incomplete; refusing to publish a partial acceptance report")
public={key:value for key,value in report.items() if key!="results"}
public["appSourceCommit"]=subprocess.check_output(["git","rev-parse","HEAD"],text=True).strip()
public["scope"]="Generated synthetic collections; original desktop Python/Rust reviewer versus the Swift collection API used by iOS. GUI task dispatch is synchronous; drawing is omitted."
public["numericTolerance"]={"absolute":1e-5,"relative":1e-5,"integerAndStringEquality":"exact","recurrentModuleHashes":"exact BLAKE2b-256 equality"}
public["totals"]={"statuses":dict(Counter(r["status"] for r in results)),
                  "reviewPreparations":sum(r["steps"] for r in results),
                  "answers":sum(r["answers"] for r in results),
                  "comparisons":sum(r["comparisons"] for r in results)}
public["results"]=[]
for result in sorted(results,key=lambda r:(r["model"],r["precision"],r["mode"],r["scenario"])):
    item={key:value for key,value in result.items() if key not in ("isolation","work")}
    item["isolation"]={name:{key:value for key,value in audit.items() if key not in ("home","python")} for name,audit in result.get("isolation",{}).items()}
    public["results"].append(item)
args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(json.dumps(public,indent=2)+"\n")
print(json.dumps(public["totals"]))
