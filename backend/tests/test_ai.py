"""Step 5: AI text and video jobs with fake providers, budget cap, retries, review flow, adapters."""
import json
from datetime import datetime, timedelta
from types import SimpleNamespace

import httpx
import pytest

from eyetracking.application.ai_use_cases import Providers
from eyetracking.domain.ai import SAMPLE_MARK
from eyetracking.infrastructure.ai.anthropic_text import AnthropicTextGenerator
from eyetracking.infrastructure.ai.fake import FailingTextGenerator, FakeTextGenerator, FakeVideoGenerator, TerminalGenerationError
from eyetracking.infrastructure.ai.heygen_video import HeyGenVideoGenerator
from eyetracking.infrastructure.uow import SqlUnitOfWork

from .conftest import auth
from .test_measurement import make_ready
from .test_practice import INTEREST, publish


def interest_assignment(world) -> int:
    c = world.c
    make_ready(world, world.p1)
    c.put("/me/profile", json={"display_name": "Sam", "interests": ["Trains", "Gardening"]}, headers=auth(world.p1))
    interest = publish(world, INTEREST, "Interest")
    aid = c.post(f"/studies/{world.study_a}/participants/P-001/assignments", json={"protocol_id": interest}, headers=auth(world.researcher_a)).json()["id"]
    c.post(f"/me/assignments/{aid}/topic", json={"topic": "Trains", "free_text": "steam engines please"}, headers=auth(world.p1))
    return aid


def test_text_and_video_flow_with_fake_providers(world):
    c = world.c
    base = f"/studies/{world.study_a}/ai"
    st = c.get(f"{base}/status", headers=auth(world.analyst_a)).json()
    assert st["text_provider"] == {"name": "fake-text", "model": "sample-script", "configured": True, "synthetic": True}
    assert st["video_provider"]["synthetic"] is True and st["budget"]["cost_cap_units"] == 0 and st["worker"]["enabled"] is False
    assert c.get(f"{base}/status", headers=auth(world.researcher_b)).status_code == 403
    aid = interest_assignment(world)
    # text job from the assignment: topic, name and interests come from the record; free text stays home by default
    assert c.post(f"{base}/text-jobs", json={"assignment_id": aid}, headers=auth(world.analyst_a)).status_code == 403
    r = c.post(f"{base}/text-jobs", json={"assignment_id": aid, "interaction_points": 2}, headers=auth(world.researcher_a))
    assert r.status_code == 201, r.text
    job = r.json()
    assert job["kind"] == "text" and job["status"] == "queued" and job["provider"] == "fake-text" and job["cost_estimate_units"] == 0
    assert job["request"] == {"topic": "Trains", "display_name": "Sam", "interests": ["Trains", "Gardening"], "interaction_points": 2, "length_seconds": 90, "free_text_included": False}
    assert job["content_title"] == "AI draft: Trains"
    assert c.post(f"{base}/text-jobs", json={"topic": "", "display_name": "x"}, headers=auth(world.researcher_a)).status_code == 422
    assert c.post(f"{base}/text-jobs", json={"topic": "Birds", "interaction_points": 9}, headers=auth(world.researcher_a)).status_code == 422
    # run the queue
    r = c.post(f"{base}/run", headers=auth(world.researcher_a))
    assert r.status_code == 200 and r.json() == {"processed": 1, "succeeded": 1, "failed": 0}
    job = c.get(f"{base}/jobs/{job['id']}", headers=auth(world.researcher_a)).json()
    assert job["status"] == "succeeded" and job["result"]["segments"] == 3 and job["finished_at"] is not None
    content = c.get(f"/studies/{world.study_a}/content/{job['content_id']}", headers=auth(world.researcher_a)).json()
    assert content["status"] == "draft" and content["text_reviewed"] is False and content["media_keys"] == ["s1.webm", "s2.webm", "s3.webm"]
    assert SAMPLE_MARK in content["definition"]["segments"][0]["text"] and "Sam" in content["definition"]["segments"][0]["text"]
    assert content["definition"]["segments"][0]["question"]["branches"] == {"How it started": "s2", "What people enjoy about it": "s2"}
    assert c.get("/me/assignments", headers=auth(world.p1)).json()[0]["status"] == "content_pending"
    # videos need reviewed text
    r = c.post(f"{base}/video-jobs", json={"content_id": content["id"]}, headers=auth(world.researcher_a))
    assert r.status_code == 409
    r = c.post(f"/studies/{world.study_a}/content/{content['id']}/text-reviewed", headers=auth(world.researcher_a))
    assert r.status_code == 200 and r.json()["text_reviewed"] is True
    # editing the text resets the review flag
    edited = dict(content["definition"])
    edited["segments"][0]["text"] = "Edited by the researcher."
    r = c.put(f"/studies/{world.study_a}/content/{content['id']}", json={"definition": edited}, headers=auth(world.researcher_a))
    assert r.json()["text_reviewed"] is False
    c.post(f"/studies/{world.study_a}/content/{content['id']}/text-reviewed", headers=auth(world.researcher_a))
    r = c.post(f"{base}/video-jobs", json={"content_id": content["id"], "face_id": "f1", "voice_id": "v1"}, headers=auth(world.researcher_a))
    assert r.status_code == 201 and [j["segment_id"] for j in r.json()] == ["s1", "s2", "s3"] and r.json()[0]["provider"] == "fake-video"
    r = c.post(f"{base}/run?max_jobs=2", headers=auth(world.researcher_a))
    assert r.json()["processed"] == 2
    r = c.post(f"{base}/run", headers=auth(world.researcher_a))
    assert r.json() == {"processed": 1, "succeeded": 1, "failed": 0}
    content = c.get(f"/studies/{world.study_a}/content/{content['id']}", headers=auth(world.researcher_a)).json()
    assert content["missing_media"] == []
    media = c.get(f"/studies/{world.study_a}/content/{content['id']}/media", headers=auth(world.researcher_a)).json()
    assert [m["key"] for m in media] == ["s1.webm", "s2.webm", "s3.webm"] and media[0]["content_type"] == "video/webm" and media[0]["size"] > 1000
    assert c.get(media[0]["url"]).status_code == 200
    assert c.post(f"{base}/video-jobs", json={"content_id": content["id"]}, headers=auth(world.researcher_a)).status_code == 422  # nothing left to generate
    # approve, attach, and the participant sees the generated content with signed links
    assert c.post(f"/studies/{world.study_a}/content/{content['id']}/approve", headers=auth(world.researcher_a)).status_code == 200
    r = c.put(f"/studies/{world.study_a}/participants/P-001/assignments/{aid}", json={"content_id": content["id"]}, headers=auth(world.researcher_a))
    assert r.json()["status"] == "ready"
    mine = c.get(f"/me/assignments/{aid}/content", headers=auth(world.p1)).json()
    assert mine["segments"][0]["media_url"].startswith("/media/") and mine["segments"][0]["text"] == "Edited by the researcher."
    jobs = c.get(f"{base}/jobs", headers=auth(world.analyst_a)).json()
    assert len(jobs) == 4 and jobs[0]["kind"] == "video"
    assert len(c.get(f"{base}/jobs?status=succeeded&content_id={content['id']}", headers=auth(world.researcher_a)).json()) == 4
    actions = [e["action"] for e in c.get(f"/studies/{world.study_a}/access-log", headers=auth(world.researcher_a)).json()]
    assert actions.count("ai_job_run") == 4 and actions.count("ai_job_created") == 2


def test_budget_cap_retries_and_terminal_failures(world):
    c = world.c
    base = f"/studies/{world.study_a}/ai"
    app = c.app
    app.state.ai_providers = Providers(text=FailingTextGenerator(failures=1, cost=1.5), video=FakeVideoGenerator())
    # a paid provider needs a cap
    r = c.post(f"{base}/text-jobs", json={"topic": "Birds", "display_name": "Kim"}, headers=auth(world.researcher_a))
    assert r.status_code == 422 and r.json()["detail"].startswith("budget_exceeded")
    assert c.put(f"{base}/budget", json={"cost_cap_units": 5}, headers=auth(world.researcher_a)).status_code == 403
    r = c.put(f"{base}/budget", json={"cost_cap_units": 5, "send_free_text": True}, headers=auth(world.admin))
    assert r.status_code == 200 and r.json()["cost_cap_units"] == 5 and r.json()["send_free_text"] is True
    assert c.put(f"{base}/budget", json={"cost_cap_units": -1}, headers=auth(world.admin)).status_code == 422
    job = c.post(f"{base}/text-jobs", json={"topic": "Birds", "display_name": "Kim"}, headers=auth(world.researcher_a)).json()
    assert job["cost_estimate_units"] == 1.5
    # three jobs of 1.5 fit; the fourth would exceed the cap of 5
    c.post(f"{base}/text-jobs", json={"topic": "Bees"}, headers=auth(world.researcher_a))
    c.post(f"{base}/text-jobs", json={"topic": "Boats"}, headers=auth(world.researcher_a))
    assert c.post(f"{base}/text-jobs", json={"topic": "Bikes"}, headers=auth(world.researcher_a)).status_code == 201  # spent is still 0; estimates are not reserved
    # first pass: the provider fails once -> job re-queued with backoff, not failed
    r = c.post(f"{base}/run?max_jobs=1", headers=auth(world.researcher_a))
    assert r.json() == {"processed": 1, "succeeded": 0, "failed": 0}
    j = c.get(f"{base}/jobs/{job['id']}", headers=auth(world.researcher_a)).json()
    assert j["status"] == "queued" and j["attempts"] == 1 and "provider unavailable" in j["error"] and j["next_attempt_at"] is not None
    # backoff: the job is skipped until next_attempt_at; other queued jobs run
    r = c.post(f"{base}/run?max_jobs=1", headers=auth(world.researcher_a))
    assert r.json()["processed"] == 1
    assert c.get(f"{base}/jobs/{job['id']}", headers=auth(world.researcher_a)).json()["attempts"] == 1
    uow = SqlUnitOfWork(app.state.session_factory)
    try:
        row = uow.jobs.get(job["id"])
        row.next_attempt_at = datetime.utcnow() - timedelta(seconds=1)
        uow.commit()
    finally:
        uow.close()
    r = c.post(f"{base}/run?max_jobs=1", headers=auth(world.researcher_a))
    assert r.json() == {"processed": 1, "succeeded": 1, "failed": 0}
    j = c.get(f"{base}/jobs/{job['id']}", headers=auth(world.researcher_a)).json()
    assert j["status"] == "succeeded" and j["cost_actual_units"] == 1.5
    st = c.get(f"{base}/status", headers=auth(world.researcher_a)).json()
    assert st["budget"]["spent_units"] == 3.0 and st["budget"]["remaining_units"] == 2.0
    # now a 1.5 job still fits (3.0 + 1.5 <= 5) but two do not
    assert c.post(f"{base}/text-jobs", json={"topic": "Bugs"}, headers=auth(world.researcher_a)).status_code == 201
    # terminal failure (refusal) fails at once and can be retried by hand; cancel only queued
    app.state.ai_providers = Providers(text=FailingTextGenerator(failures=99, cost=0.0, terminal=True), video=FakeVideoGenerator())
    job2 = c.post(f"{base}/text-jobs", json={"topic": "Cats"}, headers=auth(world.researcher_a)).json()
    c.post(f"{base}/run?max_jobs=50", headers=auth(world.researcher_a))
    j2 = c.get(f"{base}/jobs/{job2['id']}", headers=auth(world.researcher_a)).json()
    assert j2["status"] == "failed" and "refusal" in j2["error"] and j2["attempts"] == 1
    assert c.post(f"{base}/jobs/{job2['id']}/cancel", headers=auth(world.researcher_a)).status_code == 409
    assert c.post(f"{base}/jobs/{job2['id']}/retry", headers=auth(world.researcher_a)).json()["status"] == "queued"
    assert c.post(f"{base}/jobs/{job2['id']}/cancel", headers=auth(world.researcher_a)).json()["status"] == "cancelled"
    assert c.post(f"{base}/jobs/{job2['id']}/retry", headers=auth(world.researcher_a)).status_code == 409
    assert c.post(f"{base}/jobs/{job2['id']}/cancel", headers=auth(world.analyst_a)).status_code == 403


def test_worker_run_once_processes_jobs(world):
    c = world.c
    from eyetracking.infrastructure.ai.worker import AiWorker

    app = c.app
    c.post(f"/studies/{world.study_a}/ai/text-jobs", json={"topic": "Trains"}, headers=auth(world.researcher_a))
    worker = AiWorker(app.state.session_factory, app.state.ai_providers, app.state.media_store, app.state.clock, 1)
    assert worker.run_once() == {"processed": 1, "succeeded": 1, "failed": 0}
    assert worker.run_once() == {"processed": 0, "succeeded": 0, "failed": 0}


def test_anthropic_adapter_with_stub_client():
    from eyetracking.domain.ai import TextRequest, sample_script

    req = TextRequest("Trains", "Sam", ("trains",), 1, 60)
    script = sample_script(req)
    # the model returns branches as a list of {option, segment} and a title, per the JSON schema
    model_json = {"title": "Trains", "start_segment": "s1", "post_segment": "s3", "comprehension": script["comprehension"],
                  "segments": [{"id": s["id"], "text": s["text"], "duration_s": s["duration_s"], "question": (None if not s["question"] else {"id": s["question"]["id"], "prompt": s["question"]["prompt"], "options": s["question"]["options"], "branches": [{"option": o, "segment": t} for o, t in s["question"]["branches"].items()]})} for s in script["segments"]]}
    calls = []

    class Messages:
        def create(self, **kwargs):
            calls.append(kwargs)
            return SimpleNamespace(stop_reason="end_turn", model="claude-opus-5-5", content=[SimpleNamespace(type="text", text=json.dumps(model_json))], usage=SimpleNamespace(input_tokens=1000, output_tokens=2000))

    client = SimpleNamespace(beta=SimpleNamespace(messages=Messages()))
    gen = AnthropicTextGenerator(api_key=None, model="claude-opus-5-5", client=client)
    assert gen.info() == {"name": "anthropic", "model": "claude-opus-5-5", "configured": True, "synthetic": False}
    assert gen.estimate_cost(req) == 0.066
    data, meta = gen.generate(req)
    assert data["segments"][0]["question"]["branches"][0] == {"option": "How it started", "segment": "s2"}
    assert meta["cost_actual_units"] == 0.044 and meta["input_tokens"] == 1000
    kw = calls[0]
    assert kw["model"] == "claude-opus-5-5" and kw["output_config"]["format"]["type"] == "json_schema" and kw["fallbacks"] == "default"
    assert kw["betas"] == ["server-side-fallback-2026-07-01"] and "Trains" in kw["messages"][0]["content"] and "Sam" in kw["messages"][0]["content"]
    assert "email" not in kw["messages"][0]["content"].lower()

    class Refusing:
        def create(self, **kwargs):
            return SimpleNamespace(stop_reason="refusal", stop_details=SimpleNamespace(category="general_harms"), content=[], usage=None, model="x")

    with pytest.raises(TerminalGenerationError, match="refusal: general_harms"):
        AnthropicTextGenerator(api_key=None, client=SimpleNamespace(beta=SimpleNamespace(messages=Refusing()))).generate(req)
    with pytest.raises(TerminalGenerationError, match="provider_not_configured"):
        AnthropicTextGenerator(api_key=None).generate(req)
    # the unconfigured adapter says so without a network call
    assert AnthropicTextGenerator(api_key=None).info()["configured"] is False


def test_heygen_adapter_with_mock_transport():
    polls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/v2/video/generate":
            body = json.loads(request.content)
            assert request.headers["x-api-key"] == "k" and body["video_inputs"][0]["voice"]["input_text"] == "Hello there"
            return httpx.Response(200, json={"data": {"video_id": "vid-1"}})
        if request.url.path == "/v1/video_status.get":
            polls["n"] += 1
            if polls["n"] < 2:
                return httpx.Response(200, json={"data": {"status": "processing"}})
            return httpx.Response(200, json={"data": {"status": "completed", "video_url": "https://cdn.example/vid-1.mp4", "duration": 12}})
        if request.url.host == "cdn.example":
            return httpx.Response(200, content=b"MP4DATA", headers={"content-type": "video/mp4"})
        return httpx.Response(404)

    gen = HeyGenVideoGenerator("k", transport=httpx.MockTransport(handler), poll_interval_s=0, sleep=lambda s: None)
    assert gen.info() == {"name": "heygen", "configured": True, "synthetic": False}
    assert gen.estimate_cost("one two three four five six seven eight nine ten", 0) == round(10 / 2.5 / 60, 4)
    data, ctype, meta = gen.generate("Hello there", "avatar-1", "voice-1")
    assert data == b"MP4DATA" and ctype == "video/mp4" and meta["cost_actual_units"] == 0.2 and meta["video_id"] == "vid-1"

    def failing(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/v2/video/generate":
            return httpx.Response(401, json={"error": "bad key"})
        return httpx.Response(500)

    with pytest.raises(TerminalGenerationError, match="heygen 401"):
        HeyGenVideoGenerator("k", transport=httpx.MockTransport(failing), sleep=lambda s: None).generate("x", "a", "v")
    with pytest.raises(TerminalGenerationError, match="provider_not_configured"):
        HeyGenVideoGenerator(None).generate("x", "a", "v")
    with pytest.raises(TerminalGenerationError, match="face_id and voice_id"):
        HeyGenVideoGenerator("k").generate("x", "", "")
