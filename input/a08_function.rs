fn another_function() {
    println("another_function");
}

// Function that returns a boolean value
fn is_divisible_by(lhs: i32, rhs: i32) -> bool {
    // Corner case, early return
    if rhs == 0 {
        return false;
    }

    // This is an expression, the `return` keyword is not necessary here
    lhs % rhs == 0
}

fn main() {
    another_function();
    let x: i32 = 3;
    let y: i32 = 2;
    if is_divisible_by(x, y) {
        println("divisible");
    } else {
        println("not divisible");
    }
}

