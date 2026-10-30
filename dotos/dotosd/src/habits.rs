//! Habits: a name, how often, and the days it was done.
//! Stored in $XDG_DATA_HOME/dotos/habits.json:
//!   [{ "name": "Gym", "icon": "fitness_center", "per_week": 3, "days": ["2026-10-16", …] }]
//! `per_week` 7 = daily. A streak counts consecutive periods that met the target.

use crate::paths;
use chrono::{Datelike, Duration, Local, NaiveDate};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Habit {
    pub name: String,
    #[serde(default)]
    pub icon: String,
    #[serde(default = "seven")]
    pub per_week: u32,
    #[serde(default)]
    pub days: Vec<String>,
}
fn seven() -> u32 { 7 }

#[derive(Debug, Clone, Serialize)]
pub struct HabitView {
    pub name: String,
    pub icon: String,
    pub per_week: u32,
    pub done_today: bool,
    pub this_week: u32,
    pub streak: u32,
    /// the last 28 days, oldest first: true = done
    pub recent: Vec<bool>,
}

pub fn load() -> Vec<Habit> {
    std::fs::read_to_string(paths::habits_file()).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
}

pub fn save(h: &[Habit]) -> std::io::Result<()> {
    paths::write_atomic(&paths::habits_file(), serde_json::to_string_pretty(h).unwrap_or_default().as_bytes())
}

fn has(h: &Habit, d: NaiveDate) -> bool {
    let k = d.format("%Y-%m-%d").to_string();
    h.days.iter().any(|x| *x == k)
}

pub fn view(h: &Habit, today: NaiveDate) -> HabitView {
    let monday = today - Duration::days(today.weekday().num_days_from_monday() as i64);
    let this_week = (0..7).map(|i| monday + Duration::days(i)).filter(|d| *d <= today && has(h, *d)).count() as u32;
    let streak = if h.per_week >= 7 {
        // daily: consecutive days up to today (today may still be pending)
        let mut d = if has(h, today) { today } else { today - Duration::days(1) };
        let mut n = 0;
        while has(h, d) { n += 1; d -= Duration::days(1); }
        n
    } else {
        // weekly target: consecutive past weeks that met it, plus this one if already met
        let mut n = if this_week >= h.per_week { 1 } else { 0 };
        let mut wk = monday - Duration::days(7);
        loop {
            let c = (0..7).filter(|i| has(h, wk + Duration::days(*i))).count() as u32;
            if c < h.per_week { break; }
            n += 1;
            wk -= Duration::days(7);
        }
        n
    };
    HabitView {
        name: h.name.clone(),
        icon: if h.icon.is_empty() { "autorenew".into() } else { h.icon.clone() },
        per_week: h.per_week,
        done_today: has(h, today),
        this_week,
        streak,
        recent: (0..28).rev().map(|i| has(h, today - Duration::days(i))).collect(),
    }
}

pub fn views() -> Vec<HabitView> {
    let today = Local::now().date_naive();
    load().iter().map(|h| view(h, today)).collect()
}

pub fn toggle(name: &str, day: NaiveDate) -> Result<bool, String> {
    let mut all = load();
    let h = all.iter_mut().find(|h| h.name.eq_ignore_ascii_case(name)).ok_or_else(|| format!("no habit '{name}'"))?;
    let k = day.format("%Y-%m-%d").to_string();
    let now_done = if let Some(i) = h.days.iter().position(|d| *d == k) { h.days.remove(i); false } else { h.days.push(k); true };
    h.days.sort();
    save(&all).map_err(|e| e.to_string())?;
    Ok(now_done)
}

pub fn add(name: &str, per_week: u32, icon: &str) -> Result<(), String> {
    let mut all = load();
    if all.iter().any(|h| h.name.eq_ignore_ascii_case(name)) {
        return Err(format!("'{name}' exists"));
    }
    all.push(Habit { name: name.into(), icon: icon.into(), per_week: per_week.clamp(1, 7), days: vec![] });
    save(&all).map_err(|e| e.to_string())
}

pub fn remove(name: &str) -> Result<(), String> {
    let mut all = load();
    let n = all.len();
    all.retain(|h| !h.name.eq_ignore_ascii_case(name));
    if all.len() == n { return Err(format!("no habit '{name}'")); }
    save(&all).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn d(s: &str) -> NaiveDate { NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap() }

    #[test]
    fn daily_streak_counts_back_from_yesterday_if_today_pending() {
        let h = Habit { name: "x".into(), icon: "".into(), per_week: 7, days: vec!["2026-10-13".into(), "2026-10-14".into(), "2026-10-15".into()] };
        assert_eq!(view(&h, d("2026-10-16")).streak, 3);
        assert!(!view(&h, d("2026-10-16")).done_today);
    }

    #[test]
    fn weekly_target_streak() {
        // weeks of 5 Oct and 28 Sep each had 3; target 3/week
        let days = ["2026-09-28", "2026-09-30", "2026-10-02", "2026-10-05", "2026-10-07", "2026-10-09"];
        let h = Habit { name: "gym".into(), icon: "".into(), per_week: 3, days: days.iter().map(|s| s.to_string()).collect() };
        // this week (from 12 Oct) is still running: it does not break the streak yet
        assert_eq!(view(&h, d("2026-10-16")).streak, 2);
        assert_eq!(view(&h, d("2026-10-11")).streak, 2);
    }
}
