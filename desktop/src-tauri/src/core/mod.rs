//! Pure logic shared by the app, mirroring `FeatherCore` in the macOS app. No Tauri or platform
//! APIs here, so it can be unit tested anywhere.

pub mod cleanup;
pub mod context;
pub mod error;
pub mod feedback;
pub mod pkce;
pub mod placement;
pub mod plus;
pub mod prompt;
pub mod recent;
pub mod reply;
pub mod reply_style;
pub mod sse;
pub mod turn;
