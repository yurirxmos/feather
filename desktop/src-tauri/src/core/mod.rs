//! Pure logic shared by the app, mirroring `FeatherCore` in the macOS app. No Tauri or platform
//! APIs here, so it can be unit tested anywhere.

pub mod context;
pub mod error;
pub mod feedback;
pub mod pkce;
pub mod placement;
pub mod plus;
pub mod prompt;
pub mod reply;
pub mod sse;
pub mod turn;
