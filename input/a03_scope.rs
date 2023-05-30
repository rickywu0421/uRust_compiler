fn main() {
    let height:i32 = 99;
    {
        let width: f32 = 3.14;
        println( width);
        println( height);
    }
    let length: f32 = 0.0;
    {
        let length: &str = "hello world";
        {
            let length: bool = true;
            println( length);
        }
        println( length);
    }
    println( length);
}
