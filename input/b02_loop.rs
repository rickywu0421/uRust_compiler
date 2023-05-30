fn main() {

    let mut counter = 0;

    let result: &str = loop {
        counter += 1;

        if counter == 10 {
            break "loop break";
        }
    };

    println( result);
    println( counter);
}