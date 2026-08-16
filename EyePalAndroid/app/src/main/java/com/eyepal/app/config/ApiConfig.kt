package com.eyepal.app.config

object ApiConfig {
    const val MOONDREAM_BASE_URL = "https://api.moondream.ai/v1/query"
    const val OPENAI_CHAT_URL = "https://api.openai.com/v1/chat/completions"
    const val OPENAI_REALTIME_CALL = "https://api.openai.com/v1/realtime/calls"
    const val OPENAI_REALTIME_TRANSLATE = "https://api.openai.com/v1/realtime/translations/calls"
    const val OPENAI_API_BASE = "https://api.openai.com/v1"
    const val CHATGPT_CODEX = "https://chatgpt.com/backend-api/codex/responses"
    const val GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta"
    const val LRCLIB_SEARCH = "https://lrclib.net/api/search"
    const val QQ_MUSIC_SEARCH = "https://u.y.qq.com/cgi-bin/musicu.fcg"
    const val QQ_MUSIC_LYRIC = "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg"
    const val QQ_MUSIC_REFERER = "https://c.y.qq.com/"
    const val OIDC_ISSUER = "https://auth.openai.com"
    const val OIDC_AUTHORIZE = "$OIDC_ISSUER/oauth/authorize"
    const val OIDC_TOKEN = "$OIDC_ISSUER/oauth/token"
    const val OIDC_REVOKE = "$OIDC_ISSUER/oauth/revoke"
    const val OIDC_REDIRECT_URI = "http://localhost:1455/auth/callback"
    const val OIDC_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
}
