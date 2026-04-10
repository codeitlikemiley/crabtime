fn main() {
    // TODO: Fix the variable declarations so this code compiles.
    // Variables are immutable by default in Rust. Use `mut` when you need to change them.

    let x = 5;
    println!("x has the value {}", x);

    x = 10;
    println!("x now has the value {}", x);

    let y = 3;
    println!("y initially is {}", y);

    y = y + 5;
    println!("y after adding 5 is {}", y);

    let message = "hello";
    println!("Message: {}", message);

    message = "goodbye";
    println!("Message: {}", message);
}
