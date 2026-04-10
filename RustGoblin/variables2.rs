pub fn compute_value(x: i32) -> i32 {
    // TODO: Use shadowing to transform x in steps:
    // 1. Shadow x to be x * 3
    // 2. Shadow x again to be x + 10
    // Return the final shadowed value

    todo!()
}

pub fn parse_string(input: &str) -> i32 {
    // TODO: Use shadowing to convert a string slice to an integer.
    // First bind input as &str, then shadow it with the parsed i32.
    // Hint: use .parse().unwrap()

    todo!()
}

pub fn scoped_shadow() -> i32 {
    let value = 10;

    // TODO: Create a block {} where you shadow `value` to be 20
    // After the block, return `value` - it should be 10 (shadowing is scoped!)
    // The block should contain: let value = 20;

    todo!()
}

fn main() {
    // You can optionally experiment here.
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compute_value_zero() {
        assert_eq!(compute_value(0), 10);
    }

    #[test]
    fn test_compute_value_positive() {
        assert_eq!(compute_value(5), 25);
        assert_eq!(compute_value(100), 310);
    }

    #[test]
    fn test_compute_value_negative() {
        assert_eq!(compute_value(-2), 4);
        assert_eq!(compute_value(-10), -20);
    }

    #[test]
    fn test_parse_string_zero() {
        assert_eq!(parse_string("0"), 0);
    }

    #[test]
    fn test_parse_string_positive() {
        assert_eq!(parse_string("42"), 42);
        assert_eq!(parse_string("999"), 999);
    }

    #[test]
    fn test_parse_string_negative() {
        assert_eq!(parse_string("-10"), -10);
        assert_eq!(parse_string("-999"), -999);
    }

    #[test]
    fn test_scoped_shadow() {
        // The outer value should be unchanged after the block
        assert_eq!(scoped_shadow(), 10);
    }
}
