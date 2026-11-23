use serde::{Deserialize, Deserializer, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EventKind {
    Keystroke,
    Cursor,
    Paste,
    Focus,
    Blur,
    AiTabSwitch,
    /// Any other (or non-string) `type`. The TS engine ignores unknown types,
    /// so this one does too instead of rejecting the whole event.
    #[serde(other)]
    Other,
}

/// Mirrors the `TelemetryEvent` contract in `packages/shared`, whose
/// discriminator field is `type` (a Rust keyword, hence `kind`).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TelemetryEvent {
    pub id: String,
    pub session_id: String,
    pub assignment_id: String,
    pub student_id: String,
    #[serde(rename = "type", deserialize_with = "deserialize_kind")]
    pub kind: EventKind,
    pub occurred_at: String,
    pub payload: serde_json::Value,
}

fn deserialize_kind<'de, D: Deserializer<'de>>(deserializer: D) -> Result<EventKind, D::Error> {
    let value = serde_json::Value::deserialize(deserializer)?;
    Ok(serde_json::from_value(value).unwrap_or(EventKind::Other))
}

/// Raw totals. `paste_volume` and `active_ms` are `f64` because the TS engine
/// works in JavaScript numbers; integer types would truncate where it does not.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EffortMetrics {
    pub keystrokes: u64,
    pub pastes: u64,
    pub paste_volume: f64,
    pub ai_tab_switches: u64,
    pub active_ms: f64,
}

/// JavaScript `Number(payload?.[field] ?? 0)`, with non-finite results mapped
/// to 0 exactly like `apps/api/src/services/effort.ts`.
fn payload_number(payload: &serde_json::Value, field: &str) -> f64 {
    let number = match payload.get(field) {
        None | Some(serde_json::Value::Null) => 0.0,
        Some(value) => js_number(value),
    };
    if number.is_finite() {
        number
    } else {
        0.0
    }
}

/// ECMAScript `ToNumber` for JSON values.
fn js_number(value: &serde_json::Value) -> f64 {
    use serde_json::Value;
    match value {
        Value::Null => 0.0,
        Value::Bool(flag) => f64::from(u8::from(*flag)),
        Value::Number(number) => number.as_f64().unwrap_or(f64::NAN),
        Value::String(text) => js_string_to_number(text),
        // ToPrimitive joins arrays with ","; only [] and [x] avoid a comma.
        Value::Array(items) => match items.as_slice() {
            [] => 0.0,
            [Value::Null] => 0.0,
            [Value::Bool(_)] | [Value::Object(_)] => f64::NAN,
            [single] => js_number(single),
            _ => f64::NAN,
        },
        Value::Object(_) => f64::NAN,
    }
}

fn is_js_whitespace(c: char) -> bool {
    matches!(
        c,
        '\u{9}' | '\u{a}' | '\u{b}' | '\u{c}' | '\u{d}' | ' ' | '\u{a0}' | '\u{1680}' | '\u{2000}'
            ..='\u{200a}'
                | '\u{2028}'
                | '\u{2029}'
                | '\u{202f}'
                | '\u{205f}'
                | '\u{3000}'
                | '\u{feff}'
    )
}

/// ECMAScript `StringToNumber`.
fn js_string_to_number(text: &str) -> f64 {
    let trimmed = text.trim_matches(is_js_whitespace);
    if trimmed.is_empty() {
        return 0.0;
    }

    for (prefix, radix) in [
        ("0x", 16),
        ("0X", 16),
        ("0o", 8),
        ("0O", 8),
        ("0b", 2),
        ("0B", 2),
    ] {
        if let Some(digits) = trimmed.strip_prefix(prefix) {
            if digits.is_empty() || !digits.chars().all(|c| c.is_digit(radix)) {
                return f64::NAN;
            }
            return match u128::from_str_radix(digits, radix) {
                Ok(value) => value as f64,
                Err(_) => digits.chars().fold(0.0, |acc, c| {
                    acc * f64::from(radix) + f64::from(c.to_digit(radix).unwrap_or(0))
                }),
            };
        }
    }

    let unsigned = trimmed.strip_prefix(['+', '-']).unwrap_or(trimmed);
    if unsigned == "Infinity" {
        return if trimmed.starts_with('-') {
            f64::NEG_INFINITY
        } else {
            f64::INFINITY
        };
    }
    // Rust's float parser also accepts "inf"/"nan"; JavaScript accepts only
    // a decimal literal here, so reject anything outside its alphabet.
    if !unsigned
        .chars()
        .all(|c| c.is_ascii_digit() || matches!(c, '.' | 'e' | 'E' | '+' | '-'))
    {
        return f64::NAN;
    }
    trimmed.parse::<f64>().unwrap_or(f64::NAN)
}

impl EffortMetrics {
    pub fn from_events(events: &[TelemetryEvent]) -> Self {
        let mut metrics = Self::default();

        for event in events {
            match event.kind {
                EventKind::Keystroke => {
                    metrics.keystrokes += 1;
                    let delta = payload_number(&event.payload, "deltaMs");
                    metrics.active_ms += delta.clamp(0.0, 5_000.0);
                }
                EventKind::Paste => {
                    metrics.pastes += 1;
                    let characters = payload_number(&event.payload, "characterCount");
                    metrics.paste_volume += characters.floor().max(0.0);
                }
                EventKind::AiTabSwitch => metrics.ai_tab_switches += 1,
                EventKind::Cursor | EventKind::Focus | EventKind::Blur | EventKind::Other => {}
            }
        }

        metrics
    }

    /// `Math.round(activeMs / 1000)`: halves round up, like the TS engine.
    pub fn active_seconds(&self) -> u64 {
        (self.active_ms / 1_000.0).round() as u64
    }

    fn paste_ratio(&self) -> f64 {
        let total_input = self.keystrokes as f64 + self.paste_volume;
        if total_input == 0.0 {
            0.0
        } else {
            self.paste_volume / total_input
        }
    }

    pub fn score(&self) -> u8 {
        let paste_penalty = (self.paste_ratio() * 100.0).min(45.0).round() as i64;
        let ai_penalty = self.ai_tab_switches.saturating_mul(10).min(30) as i64;
        let idle_penalty = if self.active_seconds() < 60 && self.pastes > 0 {
            10
        } else {
            0
        };

        (100 - paste_penalty - ai_penalty - idle_penalty).clamp(0, 100) as u8
    }

    pub fn integrity_flags(&self) -> Vec<IntegrityFlag> {
        let mut flags = Vec::new();

        if self.paste_ratio() >= 0.35 || self.paste_volume >= 500.0 {
            flags.push(IntegrityFlag::LargePaste);
        }

        if self.ai_tab_switches > 0 {
            flags.push(IntegrityFlag::AiTabSwitch);
        }

        if self.keystrokes < 100 && self.paste_volume > 200.0 {
            flags.push(IntegrityFlag::LowTypingRatio);
        }

        if self.keystrokes == 0 && self.pastes == 0 {
            flags.push(IntegrityFlag::TelemetryGap);
        }

        if flags.is_empty() {
            flags.push(IntegrityFlag::None);
        }

        flags
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum IntegrityFlag {
    None,
    LargePaste,
    AiTabSwitch,
    LowTypingRatio,
    TelemetryGap,
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn event(kind: EventKind, payload: serde_json::Value) -> TelemetryEvent {
        TelemetryEvent {
            id: "e-001".to_string(),
            session_id: "s-001".to_string(),
            assignment_id: "a-001".to_string(),
            student_id: "u-student-1".to_string(),
            kind,
            occurred_at: "2026-10-19T10:00:00Z".to_string(),
            payload,
        }
    }

    #[test]
    fn organic_typing_scores_full_marks() {
        let events: Vec<TelemetryEvent> = (0..200)
            .map(|_| event(EventKind::Keystroke, json!({ "deltaMs": 120 })))
            .collect();

        let metrics = EffortMetrics::from_events(&events);

        assert_eq!(metrics.keystrokes, 200);
        assert_eq!(metrics.active_seconds(), 24);
        assert_eq!(metrics.score(), 100);
        assert_eq!(metrics.integrity_flags(), vec![IntegrityFlag::None]);
    }

    #[test]
    fn mass_paste_reduces_score_and_flags_large_paste() {
        let events = vec![
            event(EventKind::Keystroke, json!({ "deltaMs": 100 })),
            event(EventKind::Paste, json!({ "characterCount": 1200 })),
        ];

        let metrics = EffortMetrics::from_events(&events);

        assert_eq!(metrics.paste_volume, 1200.0);
        assert!(metrics.score() < 60);
        assert!(metrics
            .integrity_flags()
            .contains(&IntegrityFlag::LargePaste));
    }

    #[test]
    fn ai_tab_switch_is_flagged_and_penalised() {
        let events = vec![
            event(EventKind::AiTabSwitch, json!({ "host": "chatgpt.com" })),
            event(EventKind::Keystroke, json!({ "deltaMs": 150 })),
        ];

        let metrics = EffortMetrics::from_events(&events);

        assert_eq!(metrics.ai_tab_switches, 1);
        assert!(metrics
            .integrity_flags()
            .contains(&IntegrityFlag::AiTabSwitch));
        assert!(metrics.score() <= 90);
    }

    #[test]
    fn events_deserialize_from_the_shared_contract_shape() {
        let parsed: TelemetryEvent = serde_json::from_value(json!({
            "id": "e-1",
            "sessionId": "s-1",
            "assignmentId": "a-001",
            "studentId": "u-student-1",
            "type": "ai_tab_switch",
            "occurredAt": "2026-10-19T10:00:00Z",
            "payload": { "host": "claude.ai" }
        }))
        .expect("contract-shaped event");
        assert_eq!(parsed.kind, EventKind::AiTabSwitch);

        let round_trip = serde_json::to_value(&parsed).expect("serialize");
        assert_eq!(round_trip["type"], "ai_tab_switch");
        assert!(round_trip.get("kind").is_none());
    }

    #[test]
    fn numeric_strings_follow_javascript_number() {
        for (text, expected) in [
            ("12", 12.0),
            (" \u{feff}12\u{3000}", 12.0),
            ("0x1F", 31.0),
            ("1e3", 1000.0),
            (".5", 0.5),
            ("-Infinity", f64::NEG_INFINITY),
        ] {
            assert_eq!(js_string_to_number(text), expected, "{text:?}");
        }
        for text in [
            "inf", "nan", "NaN", "infinity", "-0x1", "1_0", "0x", "1e", "\u{85}1",
        ] {
            assert!(js_string_to_number(text).is_nan(), "{text:?}");
        }
    }

    /// Same fixture file as apps/api/test/telemetry-scoring.test.ts.
    #[test]
    fn scoring_matches_the_shared_parity_fixture() {
        let fixture: serde_json::Value =
            serde_json::from_str(include_str!("../tests/fixtures/scoring-parity.json"))
                .expect("fixture is valid JSON");
        let cases = fixture["cases"].as_array().expect("cases");
        assert!(!cases.is_empty());

        for case in cases {
            let name = case["name"].as_str().unwrap_or("?");
            let raw: Vec<serde_json::Value> = match &case["events"] {
                serde_json::Value::Array(items) => items.clone(),
                spec => {
                    let count = spec["repeat"].as_u64().expect("repeat count");
                    let one = json!({ "type": spec["type"], "payload": spec["payload"] });
                    (0..count).map(|_| one.clone()).collect()
                }
            };
            let events: Vec<TelemetryEvent> = raw
                .into_iter()
                .enumerate()
                .map(|(index, item)| {
                    serde_json::from_value(json!({
                        "id": format!("e-{index}"),
                        "sessionId": "s-parity",
                        "assignmentId": "a-001",
                        "studentId": "u-student-1",
                        "type": item["type"],
                        "occurredAt": "2026-10-19T10:00:00Z",
                        "payload": item["payload"],
                    }))
                    .expect("fixture event deserializes")
                })
                .collect();

            let metrics = EffortMetrics::from_events(&events);
            let expected = &case["expected"];
            let flags = serde_json::to_value(metrics.integrity_flags()).expect("flags");
            assert_eq!(
                metrics.keystrokes,
                expected["keystrokes"].as_u64().unwrap(),
                "{name}"
            );
            assert_eq!(
                metrics.pastes,
                expected["pastes"].as_u64().unwrap(),
                "{name}"
            );
            assert_eq!(
                metrics.paste_volume,
                expected["pasteVolume"].as_f64().unwrap(),
                "{name}"
            );
            assert_eq!(
                metrics.ai_tab_switches,
                expected["aiTabSwitches"].as_u64().unwrap(),
                "{name}"
            );
            assert_eq!(
                metrics.active_seconds(),
                expected["activeSeconds"].as_u64().unwrap(),
                "{name}"
            );
            assert_eq!(
                u64::from(metrics.score()),
                expected["score"].as_u64().unwrap(),
                "{name}"
            );
            assert_eq!(flags, expected["flags"], "{name}");
        }
    }
}
