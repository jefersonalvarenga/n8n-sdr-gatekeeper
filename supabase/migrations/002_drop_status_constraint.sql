-- ============================================
-- Migration 002: Remove CHECK constraint do status
-- O FastAPI pode retornar stages dinâmicos (ex: opening, negotiating)
-- que não estavam previstos no constraint original
-- ============================================

ALTER TABLE gk_conversations DROP CONSTRAINT IF EXISTS gk_conversations_status_check;
