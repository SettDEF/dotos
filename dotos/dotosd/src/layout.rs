//! A graph's layout, computed once (`dotos graph --layout`): forces as the window's own simulation
//! (points push apart, links pull, a weak pull to the middle), with Barnes–Hut so a big graph is
//! O(n log n) a step. The window starts from these places and only fine-tunes, so it settles fast
//! and then costs nothing.

use serde_json::Value;
use std::collections::HashMap;

/// A quadtree cell: its bounds, the mass in it and its centre, its four children.
struct Cell {
    x0: f64,
    y0: f64,
    size: f64,
    mass: f64,
    cx: f64,
    cy: f64,
    kids: Option<Box<[Cell; 4]>>,
    /// the one point in a leaf
    one: Option<usize>,
}

impl Cell {
    fn new(x0: f64, y0: f64, size: f64) -> Cell {
        Cell { x0, y0, size, mass: 0.0, cx: 0.0, cy: 0.0, kids: None, one: None }
    }

    fn quad(&self, x: f64, y: f64) -> usize {
        let h = self.size / 2.0;
        usize::from(x >= self.x0 + h) + 2 * usize::from(y >= self.y0 + h)
    }

    fn insert(&mut self, i: usize, p: &[(f64, f64)], depth: u32) {
        let (x, y) = p[i];
        self.cx = (self.cx * self.mass + x) / (self.mass + 1.0);
        self.cy = (self.cy * self.mass + y) / (self.mass + 1.0);
        self.mass += 1.0;
        if self.kids.is_none() && self.one.is_none() {
            self.one = Some(i);
            return;
        }
        if self.kids.is_none() {
            // split: the point that was here goes down too (points on one spot stop splitting)
            if depth > 24 {
                return;
            }
            let h = self.size / 2.0;
            let (x0, y0) = (self.x0, self.y0);
            self.kids = Some(Box::new([Cell::new(x0, y0, h), Cell::new(x0 + h, y0, h), Cell::new(x0, y0 + h, h), Cell::new(x0 + h, y0 + h, h)]));
            if let Some(j) = self.one.take() {
                let q = self.quad(p[j].0, p[j].1);
                self.kids.as_mut().unwrap()[q].insert(j, p, depth + 1);
            }
        }
        let q = self.quad(x, y);
        self.kids.as_mut().unwrap()[q].insert(i, p, depth + 1);
    }

    /// The push on point `i` (at x, y) from this cell; far cells count as one mass (theta).
    fn push(&self, i: usize, x: f64, y: f64, k: f64, out: &mut (f64, f64)) {
        if self.mass == 0.0 || self.one == Some(i) && self.kids.is_none() {
            return;
        }
        let (dx, dy) = (x - self.cx, y - self.cy);
        let d2 = dx * dx + dy * dy;
        if self.kids.is_none() || self.size * self.size < 0.64 * d2 {
            let d2 = d2.max(1.0);
            let f = k * self.mass / (d2 + 200.0);
            let d = d2.sqrt();
            out.0 += dx / d * f;
            out.1 += dy / d * f;
            return;
        }
        for c in self.kids.as_ref().unwrap().iter() {
            c.push(i, x, y, k, out);
        }
    }
}

/// Places for the graph's nodes (`x`, `y` added to each), `steps` steps of the simulation. A node
/// that already has a place (`known`, by id) starts there and moves less.
pub fn place(graph: &mut Value, known: &HashMap<String, (f64, f64)>, steps: usize) {
    let Some(nodes) = graph["nodes"].as_array() else { return };
    let n = nodes.len();
    if n == 0 {
        return;
    }
    let index: HashMap<String, usize> = nodes.iter().enumerate().filter_map(|(i, v)| Some((v["id"].as_str()?.to_string(), i))).collect();
    let links: Vec<(usize, usize, f64)> = graph["edges"]
        .as_array()
        .map(|es| es.iter().filter_map(|e| Some((*index.get(e["a"].as_str()?)?, *index.get(e["b"].as_str()?)?, if e["kind"] == "link" || e["kind"] == "embed" { 70.0 } else { 48.0 }))).collect())
        .unwrap_or_default();
    // a spiral, or where it was
    let mut p: Vec<(f64, f64)> = nodes
        .iter()
        .enumerate()
        .map(|(i, v)| {
            v["id"].as_str().and_then(|id| known.get(id)).copied().unwrap_or_else(|| {
                let (a, r) = (i as f64 * 2.399963, 30.0 * ((i + 1) as f64).sqrt());
                (r * a.cos(), r * a.sin())
            })
        })
        .collect();
    let mut v = vec![(0.0, 0.0); n];
    let mut alpha = 1.0;
    for _ in 0..steps {
        let (mut x0, mut y0, mut x1, mut y1) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
        for &(x, y) in &p {
            x0 = x0.min(x);
            y0 = y0.min(y);
            x1 = x1.max(x);
            y1 = y1.max(y);
        }
        let mut root = Cell::new(x0 - 1.0, y0 - 1.0, (x1 - x0).max(y1 - y0) + 2.0);
        for i in 0..n {
            root.insert(i, &p, 0);
        }
        for i in 0..n {
            let mut f = (0.0, 0.0);
            root.push(i, p[i].0, p[i].1, 2400.0 * alpha, &mut f);
            v[i].0 += f.0 - p[i].0 * 0.012 * alpha;
            v[i].1 += f.1 - p[i].1 * 0.012 * alpha;
        }
        for &(a, b, len) in &links {
            let (dx, dy) = (p[b].0 - p[a].0, p[b].1 - p[a].1);
            let d = (dx * dx + dy * dy).sqrt().max(1.0);
            let f = (d - len) * 0.05 * alpha;
            let (fx, fy) = (dx / d * f, dy / d * f);
            v[a].0 += fx;
            v[a].1 += fy;
            v[b].0 -= fx;
            v[b].1 -= fy;
        }
        for i in 0..n {
            v[i].0 *= 0.62;
            v[i].1 *= 0.62;
            p[i].0 += v[i].0;
            p[i].1 += v[i].1;
        }
        alpha *= 0.985;
    }
    if let Some(nodes) = graph["nodes"].as_array_mut() {
        for (i, node) in nodes.iter_mut().enumerate() {
            node["x"] = serde_json::json!((p[i].0 * 10.0).round() / 10.0);
            node["y"] = serde_json::json!((p[i].1 * 10.0).round() / 10.0);
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    #[test]
    fn linked_points_end_near_and_strangers_apart() {
        let mut g = json!({ "nodes": [{ "id": "a" }, { "id": "b" }, { "id": "c" }], "edges": [{ "a": "a", "b": "b", "kind": "link" }] });
        super::place(&mut g, &Default::default(), 300);
        let at = |i: usize| (g["nodes"][i]["x"].as_f64().unwrap(), g["nodes"][i]["y"].as_f64().unwrap());
        let d = |a: (f64, f64), b: (f64, f64)| ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt();
        assert!(d(at(0), at(1)) < d(at(0), at(2)), "linked closer than not: {:?} {:?} {:?}", at(0), at(1), at(2));
        assert!(d(at(0), at(1)) > 20.0, "but not on top of each other");
    }
}
