// I AM NOT DONE

pub struct LruCache {
    // TODO: choose your data structures
}

impl LruCache {
    pub fn new(capacity: usize) -> Self {
        let _ = capacity;
        todo!("create a cache with the given capacity")
    }

    pub fn get(&mut self, key: i32) -> Option<i32> {
        let _ = key;
        todo!("return value and mark as recently used")
    }

    pub fn put(&mut self, key: i32, value: i32) {
        let _ = (key, value);
        todo!("insert or update, evict LRU if over capacity")
    }
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