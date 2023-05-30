fn main(){
    let s: &str = "Hello World";
    let hello: &str = &s[..5];
    let space: &str = &s[5..6];
    let world: &str = &s[6..];
    print(hello);
    print(space);
    println(world);
}