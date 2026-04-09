use std::collections::{HashMap, VecDeque};

pub struct LruCache {
    capacity: usize,
    map: HashMap<i32, i32>,
    order: VecDeque<i32>,
}

impl LruCache {
    pub fn new(capacity: usize) -> Self {
        Self {
            capacity,
            map: HashMap::new(),
            order: VecDeque::new(),
        }
    }

    pub fn get(&mut self, key: i32) -> Option<i32> {
        if let Some(&value) = self.map.get(&key) {
            self.promote(key);
            Some(value)
        } else {
            None
        }
    }

    pub fn put(&mut self, key: i32, value: i32) {
        if self.map.contains_key(&key) {
            self.map.insert(key, value);
            self.promote(key);
            return;
        }

        if self.map.len() == self.capacity {
            if let Some(lru) = self.order.pop_front() {
                self.map.remove(&lru);
            }
        }

        self.map.insert(key, value);
        self.order.push_back(key);
    }

    fn promote(&mut self, key: i32) {
        if let Some(position) = self.order.iter().position(|candidate| *candidate == key) {
            self.order.remove(position);
        }
        self.order.push_back(key);
    }
}