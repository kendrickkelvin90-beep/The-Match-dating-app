use axum::{
    extract::State,
    http::{header::AUTHORIZATION, HeaderMap, StatusCode},
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::{env, net::SocketAddr, sync::Arc, time::Duration};
use uuid::Uuid;

#[derive(Clone)]
struct AppState {
    supabase_url: String,
    supabase_anon_key: String,
    http: Client,
}

#[derive(Deserialize)]
struct AuthorizeRequest {
    target_user_id: Uuid,
}

#[derive(Serialize)]
struct AuthorizeResponse {
    authorized: bool,
}

#[derive(Serialize)]
struct ErrorResponse {
    error: &'static str,
}

#[derive(Deserialize)]
struct SupabaseUser {
    id: Uuid,
}

fn error(status: StatusCode, message: &'static str) -> axum::response::Response {
    (status, Json(ErrorResponse { error: message })).into_response()
}

fn bearer_token(headers: &HeaderMap) -> Option<&str> {
    let value = headers.get(AUTHORIZATION)?.to_str().ok()?;
    let (scheme, token) = value.split_once(' ')?;
    if !scheme.eq_ignore_ascii_case("bearer") || token.trim().is_empty() {
        return None;
    }
    Some(token.trim())
}

async fn health() -> impl IntoResponse {
    (StatusCode::OK, Json(serde_json::json!({
        "status": "ok",
        "service": "the-match-chat-service"
    })))
}

// This endpoint deliberately performs authorization only. It does not send,
// edit, delete, or otherwise mutate messages. The existing chat remains live
// on Supabase until a separately reviewed integration is approved.
async fn authorize_chat(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<AuthorizeRequest>,
) -> impl IntoResponse {
    let Some(token) = bearer_token(&headers) else {
        return error(StatusCode::UNAUTHORIZED, "Sign-in is required.");
    };

    let auth_response = match state
        .http
        .get(format!("{}/auth/v1/user", state.supabase_url))
        .header("apikey", &state.supabase_anon_key)
        .bearer_auth(token)
        .send()
        .await
    {
        Ok(response) => response,
        Err(_) => return error(StatusCode::BAD_GATEWAY, "Authentication service is temporarily unavailable."),
    };

    if auth_response.status() == StatusCode::UNAUTHORIZED
        || auth_response.status() == StatusCode::FORBIDDEN
    {
        return error(StatusCode::UNAUTHORIZED, "Your session is invalid. Please sign in again.");
    }
    if !auth_response.status().is_success() {
        return error(StatusCode::BAD_GATEWAY, "Could not verify your session.");
    }

    let user: SupabaseUser = match auth_response.json().await {
        Ok(user) => user,
        Err(_) => return error(StatusCode::BAD_GATEWAY, "Could not verify your session."),
    };

    if user.id == payload.target_user_id {
        return error(StatusCode::BAD_REQUEST, "Choose another member.");
    }

    let rpc_response = match state
        .http
        .post(format!(
            "{}/rest/v1/rpc/can_interact_with_member",
            state.supabase_url
        ))
        .header("apikey", &state.supabase_anon_key)
        .bearer_auth(token)
        .json(&serde_json::json!({
            "target_user_id": payload.target_user_id
        }))
        .send()
        .await
    {
        Ok(response) => response,
        Err(_) => return error(StatusCode::BAD_GATEWAY, "Chat permissions are temporarily unavailable."),
    };

    if !rpc_response.status().is_success() {
        return error(StatusCode::BAD_GATEWAY, "Could not verify chat permissions.");
    }

    let allowed: bool = match rpc_response.json().await {
        Ok(value) => value,
        Err(_) => return error(StatusCode::BAD_GATEWAY, "Could not verify chat permissions."),
    };

    if !allowed {
        return error(StatusCode::FORBIDDEN, "This conversation is unavailable.");
    }

    (StatusCode::OK, Json(AuthorizeResponse { authorized: true })).into_response()
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            env::var("RUST_LOG").unwrap_or_else(|_| "the_match_chat_service=info,tower_http=warn".into()),
        )
        .init();

    let supabase_url = env::var("SUPABASE_URL")
        .expect("SUPABASE_URL must be configured");
    let supabase_anon_key = env::var("SUPABASE_ANON_KEY")
        .expect("SUPABASE_ANON_KEY must be configured");
    let port: u16 = env::var("PORT")
        .unwrap_or_else(|_| "8080".into())
        .parse()
        .expect("PORT must be a valid port number");

    let http = Client::builder()
        .timeout(Duration::from_secs(8))
        .build()
        .expect("HTTP client could not be initialized");

    let state = Arc::new(AppState {
        supabase_url: supabase_url.trim_end_matches('/').to_string(),
        supabase_anon_key,
        http,
    });

    let app = Router::new()
        .route("/health", get(health))
        .route("/v1/chat/authorize", post(authorize_chat))
        .with_state(state);

    let address = SocketAddr::from(([0, 0, 0, 0], port));
    let listener = tokio::net::TcpListener::bind(address)
        .await
        .expect("Could not bind HTTP listener");

    tracing::info!("The Match Rust chat service listening on {}", address);
    axum::serve(listener, app)
        .await
        .expect("HTTP server failed");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_only_bearer_authorization() {
        let mut headers = HeaderMap::new();
        headers.insert(AUTHORIZATION, "Bearer test-token".parse().unwrap());
        assert_eq!(bearer_token(&headers), Some("test-token"));

        headers.insert(AUTHORIZATION, "Basic test-token".parse().unwrap());
        assert_eq!(bearer_token(&headers), None);
    }

    #[test]
    fn rejects_empty_bearer_token() {
        let mut headers = HeaderMap::new();
        headers.insert(AUTHORIZATION, "Bearer   ".parse().unwrap());
        assert_eq!(bearer_token(&headers), None);
    }
}
