use super::*;

#[test]
fn releasing_the_process_cache_forgets_rows_and_cpu_baseline() {
    let mut sampler = ResourceSampler::default();
    let self_pid = std::process::id();
    for _ in 0..REFRESHES_BEFORE_CPU_IS_VALID {
        sampler.sample(&[], self_pid, None);
    }
    assert!(!sampler.system.processes().is_empty());
    assert!(sampler.refreshes >= REFRESHES_BEFORE_CPU_IS_VALID);

    sampler.release_process_cache();

    assert!(sampler.system.processes().is_empty());
    assert_eq!(sampler.refreshes, 0);
    assert_eq!(sampler.sample(&[], self_pid, None)["warming"], json!(true));
}
