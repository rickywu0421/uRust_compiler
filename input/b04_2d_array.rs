fn main(){
    let mut state :[[i32; 2]; 3] = [[0; 2]; 3];
    println(state[0][0]);
    println(state[0][1]);
    println(state[1][0]);
    println(state[1][1]);
    println(state[2][0]);
    println(state[2][1]);
    state[0][0] = 0;
    state[0][1] = 1;
    state[1][0] = 2;
    state[1][1] = 3;
    state[2][0] = 4;
    state[2][1] = 5;
    println(state[0][0]);
    println(state[0][1]);
    println(state[1][0]);
    println(state[1][1]);
    println(state[2][0]);
    println(state[2][1]);
}