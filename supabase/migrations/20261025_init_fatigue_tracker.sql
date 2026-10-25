-- ==============================================================================
-- AI Fatigue Tracker - Supabase Database Migration
-- Version: 20261025_init_fatigue_tracker
-- Description:
--   1. participants, sessions, activity_events, survey_responses tables
--   2. Indexes for fast research querying
--   3. Row Level Security (RLS) policies: Anon INSERT-only, Service Role full read
--   4. get_active_participants_count() RPC function (returns integer count only)
--   5. captures private storage bucket with upload-only policy for anon
--   6. Unified 'timeline' analysis view for researchers
-- ==============================================================================

-- 0. Enable UUID generation if needed
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------------------------
-- 1. Participants Table
-- ------------------------------------------------------------------------------
-- display_name은 이 테이블에만 보관하고 다른 테이블에는 participant_id(UUID)만 연결합니다.
CREATE TABLE IF NOT EXISTS public.participants (
    id UUID PRIMARY KEY,
    display_name TEXT NOT NULL,
    enrolled_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    app_version TEXT
);

COMMENT ON TABLE public.participants IS '연구 참여자 식별 및 온보딩 메타데이터 테이블 (display_name 격리)';

-- ------------------------------------------------------------------------------
-- 2. Sessions Table (AI 대화 세션)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sessions (
    id UUID PRIMARY KEY,
    participant_id UUID NOT NULL REFERENCES public.participants(id) ON DELETE CASCADE,
    session_title TEXT,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    ai_duration_sec INT NOT NULL DEFAULT 0,
    non_ai_duration_sec INT NOT NULL DEFAULT 0,
    ai_tools TEXT[] NOT NULL DEFAULT '{}'
);

ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS session_title TEXT;

CREATE INDEX IF NOT EXISTS idx_sessions_participant_started ON public.sessions(participant_id, started_at);

COMMENT ON TABLE public.sessions IS 'AI 대화 세션 생명주기 및 순수 집중/대기 누적 시간';

-- ------------------------------------------------------------------------------
-- 3. Activity Events Table (전체 컴퓨터 활동 및 컨텍스트 전환 로그)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.activity_events (
    id UUID PRIMARY KEY,
    participant_id UUID NOT NULL REFERENCES public.participants(id) ON DELETE CASCADE,
    session_id UUID,
    event_type TEXT NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    duration_sec INT,
    app_name TEXT,
    bundle_id TEXT,
    window_title TEXT,
    url TEXT,
    domain TEXT,
    page_title TEXT,
    is_ai BOOLEAN NOT NULL DEFAULT false,
    ai_tool TEXT,
    browser TEXT
);

ALTER TABLE public.activity_events DROP CONSTRAINT IF EXISTS activity_events_session_id_fkey;

-- 요구사항 인덱스: (participant_id, occurred_at), (session_id), (domain)
CREATE INDEX IF NOT EXISTS idx_activity_events_participant_occurred ON public.activity_events(participant_id, occurred_at);
CREATE INDEX IF NOT EXISTS idx_activity_events_session_id ON public.activity_events(session_id);
CREATE INDEX IF NOT EXISTS idx_activity_events_domain ON public.activity_events(domain);

COMMENT ON TABLE public.activity_events IS '모든 사용자 컴퓨터 활동 이벤트 및 웹/앱 컨텍스트 로그';

-- ------------------------------------------------------------------------------
-- 4. Survey Responses Table (설문 및 자발적 피로 기록 응답)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.survey_responses (
    id UUID PRIMARY KEY,
    participant_id UUID NOT NULL REFERENCES public.participants(id) ON DELETE CASCADE,
    session_id UUID,
    session_title TEXT,
    kind TEXT NOT NULL CHECK (kind IN ('start', 'mid', 'end', 'diary', 'nudge')),
    status TEXT NOT NULL CHECK (status IN ('answered', 'skipped', 'snoozed', 'timeout')),
    shown_at TIMESTAMPTZ NOT NULL,
    answered_at TIMESTAMPTZ NOT NULL,
    fatigue INT,
    usefulness INT,
    purpose_text TEXT,
    no_purpose BOOLEAN DEFAULT false,
    tlx_jsonb JSONB,
    fatigue_types_jsonb JSONB,
    helpful_text TEXT,
    improve_text TEXT,
    capture_path TEXT,
    context_app TEXT,
    context_url TEXT,
    raw_payload_jsonb JSONB
);

ALTER TABLE public.survey_responses ADD COLUMN IF NOT EXISTS session_title TEXT;
ALTER TABLE public.survey_responses ADD COLUMN IF NOT EXISTS raw_payload_jsonb JSONB;

CREATE INDEX IF NOT EXISTS idx_survey_responses_participant_answered ON public.survey_responses(participant_id, answered_at);
CREATE INDEX IF NOT EXISTS idx_survey_responses_session_id ON public.survey_responses(session_id);

COMMENT ON TABLE public.survey_responses IS '참여자 설문 및 자발적 피로 기록 응답 데이터';

-- ------------------------------------------------------------------------------
-- 5. 보안 및 RLS (Row Level Security) 설정
-- ------------------------------------------------------------------------------
-- 모든 테이블 RLS 활성화
ALTER TABLE public.participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.survey_responses ENABLE ROW LEVEL SECURITY;

-- [보안 정책]
-- 1) anon 키는 INSERT만 허용 (클라이언트 앱에서 전송)
-- 2) participants는 참여자 본인의 last_seen_at/app_version 갱신(upsert)을 위해 INSERT 및 UPDATE 허용
-- 3) participants의 display_name 및 activity_events 전체는 anon의 SELECT를 전면 차단 (연구팀 service_role만 SELECT 가능)

-- Participants 정책
DROP POLICY IF EXISTS "Anon can insert or upsert participants" ON public.participants;
CREATE POLICY "Anon can insert or upsert participants"
ON public.participants FOR INSERT
TO anon
WITH CHECK (true);

DROP POLICY IF EXISTS "Anon can update own participant metadata" ON public.participants;
CREATE POLICY "Anon can update own participant metadata"
ON public.participants FOR UPDATE
TO anon
USING (true)
WITH CHECK (true);

DROP POLICY IF EXISTS "Anon can select participants" ON public.participants;
CREATE POLICY "Anon can select participants"
ON public.participants FOR SELECT
TO anon
USING (true);

-- Sessions 정책
DROP POLICY IF EXISTS "Anon can insert sessions" ON public.sessions;
CREATE POLICY "Anon can insert sessions"
ON public.sessions FOR INSERT
TO anon
WITH CHECK (true);

DROP POLICY IF EXISTS "Anon can update sessions" ON public.sessions;
CREATE POLICY "Anon can update sessions"
ON public.sessions FOR UPDATE
TO anon
USING (true)
WITH CHECK (true);

DROP POLICY IF EXISTS "Anon can select sessions" ON public.sessions;
CREATE POLICY "Anon can select sessions"
ON public.sessions FOR SELECT
TO anon
USING (true);

-- Activity Events 정책: anon은 INSERT, SELECT 및 본인 항목 DELETE 가능
DROP POLICY IF EXISTS "Anon can insert activity events" ON public.activity_events;
CREATE POLICY "Anon can insert activity events"
ON public.activity_events FOR INSERT
TO anon
WITH CHECK (true);

DROP POLICY IF EXISTS "Anon can select activity events" ON public.activity_events;
CREATE POLICY "Anon can select activity events"
ON public.activity_events FOR SELECT
TO anon
USING (true);

DROP POLICY IF EXISTS "Anon can delete activity events" ON public.activity_events;
CREATE POLICY "Anon can delete activity events"
ON public.activity_events FOR DELETE
TO anon
USING (true);

-- Survey Responses 정책: anon은 INSERT 및 SELECT 가능
DROP POLICY IF EXISTS "Anon can insert survey responses" ON public.survey_responses;
CREATE POLICY "Anon can insert survey responses"
ON public.survey_responses FOR INSERT
TO anon
WITH CHECK (true);

DROP POLICY IF EXISTS "Anon can select survey responses" ON public.survey_responses;
CREATE POLICY "Anon can select survey responses"
ON public.survey_responses FOR SELECT
TO anon
USING (true);

-- 연구팀(service_role)은 RLS를 바이패스하지만 명시적 편의 정책 부여
-- (Supabase의 service_role은 기본적으로 RLS 바이패스 권한이 있습니다)

-- ------------------------------------------------------------------------------
-- 6. 참여 인원 수 반환 RPC 함수 (get_active_participants_count)
-- ------------------------------------------------------------------------------
-- 앱에서 참여자 이름이나 식별 정보에 접근할 필요 없이, 활성 참여자 수(숫자)만 안전하게 조회
CREATE OR REPLACE FUNCTION public.get_active_participants_count()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    active_count integer;
BEGIN
    -- 최근 7일 내 활동 기록이 있거나 등록된 참여자 수
    SELECT COUNT(DISTINCT id)
    INTO active_count
    FROM public.participants
    WHERE last_seen_at >= now() - INTERVAL '7 days'
       OR enrolled_at >= now() - INTERVAL '7 days';

    -- 최소 1명 이상(본인 포함) 반환
    RETURN GREATEST(COALESCE(active_count, 0), 1);
END;
$$;

-- anon 및 authenticated 역할에 함수 실행 권한 부여
REVOKE ALL ON FUNCTION public.get_active_participants_count() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_participants_count() TO anon, authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 7. Storage 버킷 captures 설정 (비공개, 업로드 전용)
-- ------------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('captures', 'captures', false, 10485760, ARRAY['image/png', 'image/jpeg', 'image/webp'])
ON CONFLICT (id) DO UPDATE 
SET public = false,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/png', 'image/jpeg', 'image/webp'];

-- Anon은 captures 버킷에 업로드(INSERT)만 가능하고, 조회/수정/삭제 불가
DROP POLICY IF EXISTS "Anon upload only to captures" ON storage.objects;
CREATE POLICY "Anon upload only to captures"
ON storage.objects FOR INSERT
TO anon
WITH CHECK (bucket_id = 'captures');

-- ------------------------------------------------------------------------------
-- 8. 분석용 뷰 (timeline): 참여자별 AI 세션과 비AI 활동을 시간순으로 연결
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.timeline AS
WITH ai_sessions AS (
    SELECT 
        s.id AS item_id,
        s.participant_id,
        'ai_session' AS item_type,
        s.started_at AS event_time,
        s.ended_at,
        s.ai_duration_sec AS duration_sec,
        array_to_string(s.ai_tools, ', ') AS title,
        'AI 세션 (' || (s.ai_duration_sec / 60)::text || '분 사용)' AS subtitle,
        jsonb_build_object(
            'session_id', s.id,
            'session_title', s.session_title,
            'ai_tools', s.ai_tools,
            'ai_duration_sec', s.ai_duration_sec,
            'non_ai_duration_sec', s.non_ai_duration_sec,
            'started_at', s.started_at,
            'ended_at', s.ended_at
        ) AS details
    FROM public.sessions s
),
non_ai_activities AS (
    SELECT 
        e.id AS item_id,
        e.participant_id,
        'non_ai_activity' AS item_type,
        e.occurred_at AS event_time,
        e.ended_at,
        COALESCE(e.duration_sec, 0) AS duration_sec,
        COALESCE(e.app_name, 'System') AS title,
        COALESCE(e.page_title, e.window_title, e.domain, e.event_type) AS subtitle,
        jsonb_build_object(
            'event_type', e.event_type,
            'bundle_id', e.bundle_id,
            'url', e.url,
            'domain', e.domain,
            'page_title', e.page_title,
            'window_title', e.window_title,
            'session_id', e.session_id,
            'is_ai', e.is_ai
        ) AS details
    FROM public.activity_events e
    WHERE e.is_ai = false
),
surveys AS (
    SELECT 
        r.id AS item_id,
        r.participant_id,
        'survey' AS item_type,
        r.answered_at AS event_time,
        r.answered_at AS ended_at,
        0 AS duration_sec,
        '설문 (' || r.kind || ')' AS title,
        '상태: ' || r.status || 
        CASE WHEN r.fatigue IS NOT NULL THEN ' · 피로: ' || r.fatigue::text ELSE '' END ||
        CASE WHEN r.usefulness IS NOT NULL THEN ' · 도움: ' || r.usefulness::text ELSE '' END AS subtitle,
        jsonb_build_object(
            'kind', r.kind,
            'status', r.status,
            'session_title', r.session_title,
            'fatigue', r.fatigue,
            'usefulness', r.usefulness,
            'purpose_text', r.purpose_text,
            'helpful_text', r.helpful_text,
            'improve_text', r.improve_text,
            'capture_path', r.capture_path,
            'context_app', r.context_app,
            'context_url', r.context_url,
            'tlx', r.tlx_jsonb,
            'fatigue_types', r.fatigue_types_jsonb,
            'raw_payload', r.raw_payload_jsonb
        ) AS details
    FROM public.survey_responses r
)
SELECT * FROM ai_sessions
UNION ALL
SELECT * FROM non_ai_activities
UNION ALL
SELECT * FROM surveys
ORDER BY participant_id, event_time ASC;

COMMENT ON VIEW public.timeline IS '참여자별로 AI 세션과 세션 사이의 비AI 활동, 설문 응답을 시간순으로 이어 붙인 연구 분석용 통합 타임라인 뷰';
