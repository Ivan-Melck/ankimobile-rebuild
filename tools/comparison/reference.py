"""JSON-lines observer/driver of the unmodified desktop fork.

The actual fork modules, Collection, scheduler, RWKV coordinator, model binding,
warmup, answer metadata and undo reconciliation execute here. Context objects
replace only the main window/profile manager; no scheduling algorithm is mocked.
"""
from __future__ import annotations

import dataclasses
import contextlib
import hashlib
import json
import logging
import os
import re
import sys
import time
import traceback
from concurrent.futures import Future
from pathlib import Path
from types import SimpleNamespace

if os.environ.get("ANKI_COMPARISON_ISOLATED") != "1":
    raise SystemExit("Run through tools/comparison/run.py: audited namespace isolation is required.")

import anki.collection
from anki.cards import Card
from anki.collection import Collection
from anki import cards_pb2, scheduler_pb2
from google.protobuf.json_format import MessageToDict, ParseDict
import aqt
from aqt import rwkv_scheduler as rwkv
from aqt.rwkv_srs_benchmark import EmbeddedRwkvReviewerBackend
from aqt.reviewer import Reviewer


class Context:
    pass


failures = []
class FailOnReferenceFallback(logging.Handler):
    def emit(self, record):
        if record.levelno >= logging.ERROR:
            failures.append(record.getMessage())
logging.getLogger().addHandler(FailOnReferenceFallback())


class CompletedTasks:
    """Only the GUI dispatch transport is synchronous; fork work is unmodified."""
    def run_in_background(self, work, done, **kwargs):
        future = Future()
        try: future.set_result(work())
        except Exception as error: future.set_exception(error)
        done(future)

    def run_on_main(self, callback):
        callback()


class ObservedReviewer(Reviewer):
    """No web drawing; production fetch/undo and post-answer policies execute."""
    def __init__(self, mw):
        self.mw = mw
        self.card = None
        self._v3 = None
        self._answeredIds = []
        self._desired_retention_override = None
        self._scheduling_states_pending = False
        self._review_card_generation = 0
        self.state = "question"
        self.web_messages = []
        self.bottom = SimpleNamespace(web=SimpleNamespace(eval=self.web_messages.append))

    def check_timebox(self):
        return False  # Synthetic fixtures do not enable a timebox.

    def nextCard(self):
        self._review_card_generation += 1
        self.previous_card = self.card
        self.card = None; self._v3 = None
        self._desired_retention_override = None
        self._rwkv_undo_restored_card_active = False
        if not self._get_rwkv_undo_restored_card():
            self._get_next_v3_card()
        if self.card is not None:
            self._v3.states = rwkv.update_reviewer_scheduling_states(self._v3.states, self, self.card)
        self.state = "question"
        callbacks = getattr(self, "_rwkv_after_question_shown_callbacks", [])
        self._rwkv_after_question_shown_callbacks = []
        for callback in callbacks: callback()


def proto(value):
    return MessageToDict(value)


def digest(value):
    return hashlib.blake2b(bytes(value), digest_size=32).hexdigest() if value is not None else None


class Reference:
    def __init__(self):
        self.col = None
        self.backend = None
        self.reviewer = None
        self.mw = None
        self.queued = None

    def open(self, request):
        directory = Path(request["directory"])
        self.col = Collection(str(directory / "collection.anki2"))
        self.mw = Context()
        self.mw.col = self.col
        self.mw.pm = SimpleNamespace(profile={"rwkvModel": request["model"], "rwkvStatePrecision": request["precision"]}, profileFolder=lambda: str(directory))
        self.mw.taskman = CompletedTasks()
        self.mw.state = "review"
        self.reviewer = ObservedReviewer(self.mw)
        self.mw.reviewer = self.reviewer
        aqt.mw = self.mw
        self.backend = EmbeddedRwkvReviewerBackend(model_path=request["weights"], state_precision=request["precision"], model=request["model"])
        rwkv.set_reviewer_backend(self.backend)
        if not rwkv.warm_up_rwkv_state(self.mw, force_rebuild=True):
            raise RuntimeError("Original desktop warmup did not complete")
        return {}

    def prepare(self, request):
        if self.reviewer.card is None or request.get("refresh"):
            self.col.decks.select(int(request["deckId"]))
            rwkv.prepare_reviewer_queue_order(self.reviewer)
            self.reviewer.nextCard()
        if self.reviewer.card is None:
            return proto(self.col.sched.get_queued_cards())
        card = self.reviewer.card
        self.queued = self.reviewer._v3.queued_cards
        self.queued.cards[0].states.CopyFrom(self.reviewer._v3.states)
        result = proto(self.queued)
        # Read the original reviewer's effective displayed counters, including
        # asynchronous refresh overrides, rather than its older queue snapshot.
        remaining = self.reviewer._remaining()
        for css, key in (("new-count", "newCount"), ("learn-count", "learningCount"), ("review-count", "reviewCount")):
            match = re.search(r"class="+css+r">(.*?)</span>", remaining, re.S)
            if match:
                text = re.sub("<[^>]+>", "", match[1])
                if not text.isdecimal(): raise RuntimeError("Desktop counts have not settled: "+text)
                result[key] = int(text)
        stored = rwkv._current_reviewer_prediction(self.reviewer, card)
        if stored is None:
            raise RuntimeError("Original desktop failed to publish its review prediction")
        result["cards"][0]["rwkvPrediction"] = {
            "retrievability": stored.retrievability,
            "s90s": list(dataclasses.astuple(stored.s90_overrides)),
            "curveEnabled": stored.interval_override_used,
        }
        # This uncached query observes complete heads as well as Instant's used R.
        # Query execution must leave recurrent module state unchanged.
        before = self.recurrent()
        full = self.backend.predict_review_uncached(reviewer=self.reviewer, card=card)
        if self.recurrent() != before:
            raise RuntimeError("Reference diagnostic query changed recurrent state")
        result["fullPrediction"] = dataclasses.asdict(full) if full else None
        review_input = rwkv.rwkv_review_input(reviewer=self.reviewer, card=card, identity=rwkv.rwkv_review_identity(self.reviewer,card), ease=None)
        result["comparisonInput"] = {key:getattr(review_input,source) for key,source in (("cardType","card_type"),("dayOffset","day_offset"),("currentElapsedDays","current_elapsed_days"),("currentElapsedSeconds","current_elapsed_seconds"),("targetRetentions","target_retentions"),("enforceGradeOrder","enforce_grade_order"))}
        result["comparisonQueuePolicy"] = {"snapshot":proto(self.reviewer._v3.queued_cards),"answers":len(self.reviewer._answeredIds),"required":rwkv.reviewer_queue_order_refresh_required(self.reviewer),"due":rwkv.reviewer_queue_order_refresh_due(self.reviewer),"beforeNext":rwkv.reviewer_queue_order_refresh_before_next_card(self.reviewer)}
        return result

    def answer(self, request):
        card = self.reviewer.card
        answer = self.col.sched.build_answer(card=card, states=self.reviewer._v3.states, rating=request["rating"] - 1)
        answer.milliseconds_taken = round(request["seconds"] * 1000)
        rwkv.set_answer_rwkv_metadata(answer, self.reviewer, card, request["rating"])
        self.col.sched.answer_card(answer)
        rwkv.record_reviewer_answer(self.reviewer, card, request["rating"])
        self.reviewer.state = "transition"
        self.reviewer._after_answering(request["rating"])
        return proto(answer)

    def recurrent(self):
        if self.backend is None:
            return None
        snapshot = self.backend.cache_snapshot()
        return {"cards": {str(k): digest(v) for k, v in snapshot.card_states.items()},
                "notes": {str(k): digest(v) for k, v in snapshot.note_states.items()},
                "decks": {str(k): digest(v) for k, v in snapshot.deck_states.items()},
                "presets": {str(k): digest(v) for k, v in snapshot.preset_states.items()},
                "global": digest(snapshot.global_state)}

    def inspect(self):
        return {"tables": {name: self.col.db.all(f"select * from {name} order by " + ("oid,type" if name=="graves" else "id")) for name in ("cards", "notes", "revlog", "graves")}, "recurrent": self.recurrent()}

    def operation(self, request):
        op = request["op"]
        if op == "clock":
            return str(round(time.time() * 1000))
        if op == "isolation":
            from anki import _rsbridge
            try: launcher = Path("/usr/bin/anki").read_bytes() if Path("/usr/bin/anki").exists() else b""
            except PermissionError: launcher = b""
            return {"home": os.environ["HOME"], "python": sys.executable,
                    "rsbridge": _rsbridge.__file__,
                    "liveCollectionVisible": Path("/home/user/.local/share/Anki2").exists(),
                    "installedLauncherHidden": not launcher}
        if op == "seed":
            from fixtures import seed
            return seed(request)
        if op == "open":
            return self.open(request)
        if op == "prepare":
            return self.prepare(request)
        if op == "answer":
            return self.answer(request)
        if op in ("undo", "redo"):
            changes = getattr(self.col, op)()
            ids = getattr(rwkv, "record_collection_" + op)(changes)
            if op == "undo":
                rwkv.queue_reviewer_undo_card_ids(self.reviewer, ids)
            else:
                rwkv.apply_reviewer_redo_card_ids(self.reviewer, ids)
            self.reviewer.card = None
            return proto(changes)
        if op == "inspect":
            return self.inspect()
        if op == "queue":
            return proto(self.col.sched.get_queued_cards(fetch_limit=1000))
        if op == "queueScores":
            return {cid:proto(scheduler_pb2.RwkvRetrievabilityScoreResponse.FromString(
                self.col._backend.get_rwkv_retrievability_score_raw(cards_pb2.CardId(cid=int(cid)).SerializeToString()))).get("retrievability") for cid in request["cards"]}
        if op == "close":
            self.col.close(); self.col = None; rwkv.set_reviewer_backend(None); aqt.mw = None
            return {}
        raise ValueError("Unknown reference operation: " + op)


reference = Reference()
for line in sys.stdin:
    try:
        failures.clear()
        with contextlib.redirect_stdout(sys.stderr):
            result = reference.operation(json.loads(line))
        if failures:
            raise RuntimeError("Original reference reported an error/fallback: " + "; ".join(failures))
        print(json.dumps({"result": result}, separators=(",", ":")), flush=True)
    except Exception as error:
        traceback.print_exc(file=sys.stderr)
        print(json.dumps({"error": str(error)}), flush=True)
