//! Where the prompt panel appears, mirroring `PanelPlacement` in the macOS app. Coordinates are
//! physical pixels with a top-left origin.

use crate::platform::Rect;

/// The panel's left edge and the y coordinate its bottom edge stays anchored to while it grows.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Anchor {
    pub x: i32,
    pub bottom: i32,
}

/// Anchors the panel to the bottom of the work area, centered on the target window when known.
pub fn anchor(panel_width: u32, window_frame: Option<Rect>, work_area: Rect, inset: i32) -> Anchor {
    let safe_min_x = work_area.x + inset;
    let safe_max_x = work_area.x + work_area.width as i32 - inset;
    let mid_x = window_frame.map(|frame| frame.x + frame.width as i32 / 2).unwrap_or((safe_min_x + safe_max_x) / 2);
    let maximum = safe_max_x - panel_width as i32;
    let x = if safe_min_x <= maximum { (mid_x - panel_width as i32 / 2).clamp(safe_min_x, maximum) } else { safe_min_x };
    Anchor { x, bottom: work_area.y + work_area.height as i32 - inset }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SCREEN: Rect = Rect { x: 0, y: 0, width: 1920, height: 1040 };

    #[test]
    fn centers_on_the_target_window() {
        let window = Rect { x: 1000, y: 100, width: 600, height: 400 };
        assert_eq!(anchor(600, Some(window), SCREEN, 18), Anchor { x: 1000, bottom: 1022 });
    }

    #[test]
    fn stays_inside_the_work_area() {
        let window = Rect { x: 1800, y: 0, width: 400, height: 400 };
        assert_eq!(anchor(600, Some(window), SCREEN, 18).x, 1920 - 18 - 600);
        assert_eq!(anchor(600, None, SCREEN, 18).x, 660);
    }

    #[test]
    fn a_secondary_monitor_offsets_the_anchor() {
        let monitor = Rect { x: -1280, y: 200, width: 1280, height: 1000 };
        assert_eq!(anchor(600, None, monitor, 18), Anchor { x: -940, bottom: 1182 });
    }
}
