fn main() {
    let mut x: i32 = 0;
    println( x);
    x = 10;
    println( x);
    x += 2;
    println( x);
    x -= 3;
    println( x);
    x *= 4;
    println( x);
    x /= 5;
    println( x);
    x %= 6;
    println( x);

    let mut yy: f32 = 3.14;
    println( yy);
    yy = 10.4;
    println( yy);
    yy += 2.0;
    println( yy);
    yy -= 3.0;
    println( yy);
    yy *= 4.0;
    println( yy);
    yy /= 5.0;
    println( yy);

    let mut s: &str = "";
    println( s);
    s = "Hello";
    println( s);

    let mut bbb: bool = false;
    println( bbb);
    bbb = true;
    println( bbb);
}