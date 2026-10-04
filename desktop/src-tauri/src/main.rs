// Release builds on Windows are GUI apps; without this, launching Feather opens a console window.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    feather_desktop_lib::run()
}
