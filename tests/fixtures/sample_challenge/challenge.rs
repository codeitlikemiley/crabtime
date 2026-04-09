fn main() {
    let a = 1;
    let b = 2;
    println!("Sum: {}", a + b);
    let x = 3;
    println!("{x}");
    panic!("this is an error");
}

fn example() {
	let x = 1;
	println!("{x}");
}
#[cfg(test)]
mod tests {
 
	#[test]
   fn example() {
	 assert_eq!(true);
   }
}
