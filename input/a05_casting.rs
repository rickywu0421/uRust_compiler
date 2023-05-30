fn main() {
    let x: i32 = 3;
    let y: f32 = 3.14;
    let mut z1: i32;
    let mut z2: f32;
    z1 = x + y as i32;
    z2 = x as f32 + y;
    println( z1);
    println( z2);
    z1 = x + 6.28 as i32;
    z2 = 6 as f32 + y;
    println( z1);
    println( z2);
}