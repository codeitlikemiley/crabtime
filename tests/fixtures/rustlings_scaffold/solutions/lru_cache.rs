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
        if let std::collections::hash_map::Entry::Occupied(mut e) = self.map.entry(key) {
            e.insert(value);
            self.promote(key);
            return;
        }

        if self.map.len() == self.capacity
            && let Some(lru) = self.order.pop_front()
        {
            self.map.remove(&lru);
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

fn main() {
    // You can optionally experiment here.
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lru_basic() {
        let mut cache = LruCache::new(2);
        cache.put(1, 1);
        cache.put(2, 2);
        assert_eq!(cache.get(1), Some(1));
        cache.put(3, 3);
        assert_eq!(cache.get(2), None);
        assert_eq!(cache.get(3), Some(3));
        cache.put(4, 4);
        assert_eq!(cache.get(1), None);
        assert_eq!(cache.get(3), Some(3));
        assert_eq!(cache.get(4), Some(4));
    }
}