#[cfg(feature = "validation")]
#[test]
fn neural_heads_match_fork_published_vectors() {
    scheduling_engine::rwkv::validation::verify_all_published_vectors();
}
