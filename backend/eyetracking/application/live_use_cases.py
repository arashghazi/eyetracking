"""Use cases for build step 7, the live interactive avatar (design p. 6).

A live conversation belongs to one session of a `live_conversation` protocol. The participant
speaks or types; the reply provider proposes an answer; the domain rules decide what the avatar
says. Audio is processed in memory only. Conversation text is kept after the conversation only
when the protocol allows it and the participant agreed; otherwise only counts and flags remain.
"""
from __future__ import annotations

import time
from dataclasses import dataclass

from eyetracking.domain.ai import AiBudget
from eyetracking.domain.errors import Conflict, Invalid, NotFound
from eyetracking.domain.live import (
    AUDIO_TYPES,
    LIVE_PATH,
    MAX_AUDIO_BYTES,
    ConversationStatus,
    LiveConversation,
    LiveTurn,
    ReplyError,
    ReplyRefused,
    SpeechError,
    conversation_block,
    conversation_outcome,
    guard_reply,
    prepare_participant_text,
    render_line,
    scrub_for_storage,
    system_prompt,
    validate_live,
)
from eyetracking.domain.measurement import Session
from eyetracking.domain.models import StudyRole

from .authz import Principal, require_participant, require_study_access
from .ports import Clock, LiveAvatarProvider, LiveUnitOfWork, ReplyGenerator, SpeechToText
from .research_use_cases import log_access


@dataclass
class LiveProviders:
    reply: ReplyGenerator
    stt: SpeechToText
    avatar: LiveAvatarProvider


def _budget(uow: LiveUnitOfWork, study_id: int) -> AiBudget:
    return uow.ai_budgets.get(study_id) or AiBudget(study_id=study_id)


def _own_session(uow: LiveUnitOfWork, principal: Principal, session_id: int) -> Session:
    p = require_participant(principal)
    s = uow.sessions.get(session_id)
    if s is None or s.participant_id != p.id:
        raise NotFound("session not found")
    return s


def _live_setup(uow: LiveUnitOfWork, s: Session):
    proto = uow.protocols.get(s.protocol_id) if s.protocol_id else None
    if proto is None or proto.path != LIVE_PATH:
        raise Conflict("this session is not a live conversation")
    a = uow.assignments.get(s.assignment_id) if s.assignment_id else None
    if a is None or not a.topic:
        raise Conflict("the conversation topic has not been confirmed")
    return proto, validate_live(proto.definition.get("live")), a


def _person(uow: LiveUnitOfWork, participant_id: int) -> tuple[str | None, list[str]]:
    profile = uow.profiles.get(participant_id)
    return (profile.display_name if profile else None), (list(profile.interests or []) if profile else [])


def _turn_view(t: LiveTurn, with_text: bool = True) -> dict:
    return {"index": t.index, "role": t.role, "text": t.text if with_text else None, "chars": t.chars, "t_ms": t.t_ms, "flags": list(t.flags), "latency_ms": t.latency_ms}


def _conv_view(c: LiveConversation, cfg: dict) -> dict:
    return {
        "id": c.id,
        "status": c.status.value,
        "topic": c.topic,
        "input_mode": c.input_mode,
        "transcript_allowed": c.transcript_allowed,
        "turns_used": c.turns_used,
        "turns_left": max(0, cfg["max_turns"] - c.turns_used),
        "end_reason": c.end_reason,
        "started_at": c.started_at,
        "ended_at": c.ended_at,
        "providers": {"reply": c.reply_provider, "speech": c.stt_provider, "avatar": c.avatar_provider},
    }


def _limits(cfg: dict) -> dict:
    return {k: cfg[k] for k in ("max_turns", "max_minutes", "max_reply_words", "max_participant_chars", "input_modes")}


def _close(uow: LiveUnitOfWork, clock: Clock, c: LiveConversation, reason: str) -> None:
    if c.status is ConversationStatus.closed:
        return
    c.status = ConversationStatus.closed
    c.end_reason = reason
    c.ended_at = clock.now()
    if not c.transcript_allowed:
        for t in uow.live.turns(c.id or 0):
            t.text = None


def _add_turn(uow: LiveUnitOfWork, c: LiveConversation, role: str, text: str, t_ms: int | None, flags: list[str], latency_ms: int | None = None, cost: float = 0.0) -> LiveTurn:
    index = len(uow.live.turns(c.id or 0))
    return uow.live.add_turn(LiveTurn(conversation_id=c.id or 0, session_id=c.session_id, index=index, role=role, text=scrub_for_storage(text), chars=len(text), t_ms=t_ms, flags=flags, latency_ms=latency_ms, cost_units=cost))


def status(uow: LiveUnitOfWork, providers: LiveProviders, principal: Principal, study_id: int) -> dict:
    require_study_access(principal, study_id, StudyRole.researcher, StudyRole.analyst)
    b = _budget(uow, study_id)
    return {
        "reply_provider": providers.reply.info(),
        "speech_provider": providers.stt.info(),
        "avatar_provider": providers.avatar.info(),
        "estimates": {"per_turn_units": providers.reply.estimate_cost(), "avatar_per_minute_units": providers.avatar.estimate_cost_per_minute()},
        "budget": {"cost_cap_units": b.cost_cap_units, "spent_units": round(b.spent_units, 4), "remaining_units": round(b.remaining(), 4), "send_free_text": b.send_free_text},
        "open_conversations": len(uow.live.open_for_study(study_id)),
        "note": "Development providers are synthetic: sample rules, a sample face video and the browser's voice. No streaming avatar is connected.",
    }


def start(uow: LiveUnitOfWork, providers: LiveProviders, clock: Clock, principal: Principal, session_id: int, input_mode: str, allow_transcript: bool, t_ms: int | None) -> dict:
    s = _own_session(uow, principal, session_id)
    s.ensure_open()
    _, cfg, a = _live_setup(uow, s)
    if input_mode not in cfg["input_modes"]:
        raise Invalid("this conversation accepts: " + ", ".join(cfg["input_modes"]))
    if input_mode == "speech" and not providers.stt.info().get("configured"):
        raise Conflict("speech is not available right now; please choose typing")
    if not providers.reply.info().get("configured"):
        raise Conflict("provider_not_configured: the reply provider is not set up")
    name, _ = _person(uow, s.participant_id)
    existing = uow.live.conversation_for_session(s.id or 0)
    if existing is not None:
        if existing.status is ConversationStatus.closed:
            raise Conflict("this conversation has ended")
        turns = uow.live.turns(existing.id or 0)
        return {"conversation": _conv_view(existing, cfg), "turns": [_turn_view(t) for t in turns], "avatar": providers.avatar.client_config(cfg["avatar_id"], cfg["voice_id"]), "face_layout": cfg.get("face_layout"), "limits": _limits(cfg), "resumed": True}
    if not providers.reply.info().get("synthetic"):
        _budget(uow, s.study_id).assert_affordable(providers.reply.estimate_cost())
    c = uow.live.add_conversation(LiveConversation(
        session_id=s.id or 0, study_id=s.study_id, participant_id=s.participant_id, topic=a.topic or "", input_mode=input_mode,
        transcript_allowed=bool(cfg["store_transcript"] and allow_transcript), reply_provider=providers.reply.info()["name"],
        avatar_provider=providers.avatar.info()["name"], stt_provider=providers.stt.info()["name"], started_at=clock.now(),
    ))
    opening = _add_turn(uow, c, "avatar", render_line(cfg["opening_line"], name, c.topic), t_ms, ["scripted_line", "opening"])
    uow.commit()
    return {"conversation": _conv_view(c, cfg), "turns": [_turn_view(opening)], "avatar": providers.avatar.client_config(cfg["avatar_id"], cfg["voice_id"]), "face_layout": cfg.get("face_layout"), "limits": _limits(cfg), "resumed": False}


def _open_conversation(uow: LiveUnitOfWork, principal: Principal, session_id: int) -> tuple[Session, dict, object, LiveConversation]:
    s = _own_session(uow, principal, session_id)
    _, cfg, a = _live_setup(uow, s)
    c = uow.live.conversation_for_session(s.id or 0)
    if c is None:
        raise Conflict("start the conversation first")
    if c.status is ConversationStatus.closed:
        raise Conflict("this conversation has ended")
    s.ensure_open()
    return s, cfg, a, c


def _finish(uow: LiveUnitOfWork, clock: Clock, c: LiveConversation, cfg: dict, name: str | None, t_ms: int | None, reason: str, extra_flags: list[str]) -> dict:
    """Adds the closing line and closes. Returns the line's view taken before stored text is removed."""
    line = _add_turn(uow, c, "avatar", render_line(cfg["closing_line"], name, c.topic), t_ms, ["scripted_line", "closing", reason, *extra_flags])
    view = _turn_view(line)
    _close(uow, clock, c, reason)
    return view


def take_turn(
    uow: LiveUnitOfWork, providers: LiveProviders, clock: Clock, principal: Principal, session_id: int, expect_turn: int, t_ms: int | None,
    text: str | None = None, audio: bytes | None = None, content_type: str | None = None,
) -> dict:
    s, cfg, a, c = _open_conversation(uow, principal, session_id)
    if expect_turn != c.turns_used:
        raise Conflict("this turn was already sent; reload the conversation")
    name, interests = _person(uow, s.participant_id)
    elapsed_min = (clock.now() - c.started_at).total_seconds() / 60.0
    if elapsed_min >= cfg["max_minutes"]:
        line = _finish(uow, clock, c, cfg, name, t_ms, "time_limit", [])
        uow.commit()
        return {"participant": None, "avatar": line, "turns_used": c.turns_used, "turns_left": 0, "done": True, "end_reason": c.end_reason, "distress": False}
    in_flags: list[str] = []
    if audio is not None:
        if c.input_mode != "speech":
            raise Invalid("this conversation was started for typing")
        ctype = (content_type or "").split(";")[0].strip()
        if ctype not in AUDIO_TYPES:
            raise Invalid("unsupported audio type")
        if len(audio) > MAX_AUDIO_BYTES:
            raise Invalid("the recording is too long; please say it in a shorter way")
        try:
            heard = providers.stt.transcribe(audio, ctype, "en")
        except SpeechError as exc:
            raise Invalid(f"we could not turn that into text ({exc}); please try again or type") from exc
        finally:
            audio = None  # nothing keeps the recording
        text = heard
        in_flags.append("speech")
        if providers.stt.info().get("synthetic"):
            in_flags.append("sample_speech")
    else:
        in_flags.append("typed")
    ptext, pflags = prepare_participant_text(text, cfg["max_participant_chars"])
    budget = _budget(uow, s.study_id)
    synthetic_reply = bool(providers.reply.info().get("synthetic"))
    if not synthetic_reply:
        try:
            budget.assert_affordable(providers.reply.estimate_cost())
        except Invalid:
            _add_turn(uow, c, "participant", ptext, t_ms, in_flags + pflags)
            line = _finish(uow, clock, c, cfg, name, t_ms, "budget", [])
            c.turns_used += 1
            uow.commit()
            return {"participant": None, "avatar": line, "turns_used": c.turns_used, "turns_left": 0, "done": True, "end_reason": c.end_reason, "distress": False}
    history = [(t.role, t.text or "") for t in uow.live.turns(c.id or 0)] + [("participant", scrub_for_storage(ptext) or "")]
    free_text = a.topic_free_text if budget.send_free_text else None
    system = system_prompt(cfg, c.topic, name, interests, free_text)
    started = time.monotonic()
    data, meta, provider_flags = None, {}, []
    try:
        data, meta = providers.reply.reply(system, conversation_block(history), c.topic)
    except ReplyRefused:
        provider_flags.append("refusal")
    except ReplyError:
        provider_flags.append("provider_error")
    latency = int((time.monotonic() - started) * 1000)
    g = guard_reply(data, cfg, name, c.topic, c.off_topic_streak)
    if g.participant_on_topic is True:
        pflags.append("participant_on_topic")
    elif g.participant_on_topic is False:
        pflags.append("participant_off_topic")
    if g.distress:
        pflags.append("distress")
    c.off_topic_streak = c.off_topic_streak + 1 if g.participant_on_topic is False else 0
    cost = float(meta.get("cost_actual_units") or 0.0)
    if cost:
        budget.spent_units += cost
        uow.ai_budgets.save(budget)
        c.cost_units += cost
    part = _add_turn(uow, c, "participant", ptext, t_ms, in_flags + pflags)
    c.turns_used += 1
    reason = g.end_reason
    if reason is None and c.turns_used >= cfg["max_turns"]:
        reason = "turn_limit"
    if reason == "participant":
        avatar = _add_turn(uow, c, "avatar", g.text, t_ms, list(g.flags) + provider_flags + ["closing"], latency, cost)
    elif reason == "turn_limit":
        avatar = _add_turn(uow, c, "avatar", render_line(cfg["closing_line"], name, c.topic), t_ms, ["scripted_line", "closing", "turn_limit", *provider_flags], latency, cost)
    else:
        avatar = _add_turn(uow, c, "avatar", g.text, t_ms, list(g.flags) + provider_flags, latency, cost)
    # the participant hears and reads this reply now; stored text may be removed right after
    part_view, avatar_view = _turn_view(part), _turn_view(avatar)
    if reason in ("participant", "turn_limit"):
        _close(uow, clock, c, reason)
    uow.commit()
    return {
        "participant": part_view,
        "avatar": avatar_view,
        "turns_used": c.turns_used,
        "turns_left": max(0, cfg["max_turns"] - c.turns_used),
        "done": c.status is ConversationStatus.closed,
        "end_reason": c.end_reason,
        "distress": g.distress,
    }


def end(uow: LiveUnitOfWork, clock: Clock, principal: Principal, session_id: int, t_ms: int | None) -> dict:
    s, cfg, _, c = _open_conversation(uow, principal, session_id)
    name, _ = _person(uow, s.participant_id)
    line = _finish(uow, clock, c, cfg, name, t_ms, "participant_ended", [])
    uow.commit()
    return {"avatar": line, "turns_used": c.turns_used, "done": True, "end_reason": c.end_reason}


def my_conversation(uow: LiveUnitOfWork, principal: Principal, session_id: int) -> dict:
    s = _own_session(uow, principal, session_id)
    _, cfg, _ = _live_setup(uow, s)
    c = uow.live.conversation_for_session(s.id or 0)
    if c is None:
        return {"conversation": None, "turns": [], "limits": _limits(cfg), "store_transcript_offered": cfg["store_transcript"], "input_modes": cfg["input_modes"]}
    return {"conversation": _conv_view(c, cfg), "turns": [_turn_view(t) for t in uow.live.turns(c.id or 0)], "limits": _limits(cfg), "store_transcript_offered": cfg["store_transcript"], "input_modes": cfg["input_modes"]}


def close_on_session_end(uow: LiveUnitOfWork, clock: Clock, session: Session) -> None:
    repo = getattr(uow, "live", None)
    c = repo.conversation_for_session(session.id or 0) if repo is not None else None
    if c is not None and c.status is ConversationStatus.open:
        _close(uow, clock, c, "session_ended")


def staff_conversation(uow: LiveUnitOfWork, principal: Principal, study_id: int, session_id: int) -> dict:
    require_study_access(principal, study_id, StudyRole.researcher, StudyRole.analyst)
    s = uow.sessions.get(session_id)
    if s is None or s.study_id != study_id:
        raise NotFound("session not found")
    c = uow.live.conversation_for_session(s.id or 0)
    if c is None:
        raise NotFound("this session has no live conversation")
    proto = uow.protocols.get(s.protocol_id) if s.protocol_id else None
    cfg = validate_live((proto.definition if proto else {}).get("live") or {})
    turns = uow.live.turns(c.id or 0)
    show_text = c.transcript_allowed or c.status is ConversationStatus.open
    log_access(uow, principal, study_id, "live_transcript", {"session_id": s.id, "text_shown": bool(show_text and c.transcript_allowed)})
    uow.commit()
    return {
        "conversation": _conv_view(c, cfg),
        "turns": [_turn_view(t, with_text=c.transcript_allowed) for t in turns],
        "outcome": conversation_outcome(turns, c.end_reason),
        "cost_units": round(c.cost_units, 5),
        "note": "Text is shown only when the protocol keeps transcripts and the participant agreed. Audio is never kept.",
    }


def monitor_block(uow: LiveUnitOfWork, session_id: int) -> dict | None:
    repo = getattr(uow, "live", None)
    c = repo.conversation_for_session(session_id) if repo is not None else None
    if c is None:
        return None
    turns = repo.turns(c.id or 0)
    last = turns[-1] if turns else None
    return {
        "status": c.status.value,
        "input_mode": c.input_mode,
        "turns_used": c.turns_used,
        "distress": sum(1 for t in turns if t.role == "participant" and "distress" in t.flags),
        "redirects": sum(1 for t in turns if t.role == "avatar" and ("redirect_line" in t.flags or "fallback_line" in t.flags)),
        "last_turn": {"role": last.role, "flags": list(last.flags), "t_ms": last.t_ms} if last else None,
        "end_reason": c.end_reason,
    }
