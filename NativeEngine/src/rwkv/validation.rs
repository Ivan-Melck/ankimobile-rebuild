// Adapted from the fork’s published-vector checks. AGPL-3.0-or-later.
use super::*;
use std::io::Read;
#[derive(serde::Deserialize)]
struct VectorRow {
    features: Vec<f32>,
    ids: [i64; 5],
    skip: bool,
    elapsed: f32,
    fp32: Vec<f32>,
    int8: Vec<f32>,
}
#[derive(serde::Deserialize)]
struct Vectors {
    name: String,
    sweep: Vec<f32>,
    rows: Vec<VectorRow>,
}

fn check_published_vectors(package: &str, data: &[u8]) {
    let vectors: Vec<Vectors> = serde_json::from_slice(data).unwrap();
    for format in ["f32"] {
        let model = SrsModel::load(&PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(format!(
            "../Sources/FlashcardsCore/Resources/RWKV/{package}.bin"
        )))
        .unwrap();
        let mut maximum = 0.0_f32;
        for user in &vectors {
            let mut states = ReviewStateMaps::default();
            for (index, row) in user.rows.iter().enumerate() {
                let input = ReviewInput {
                    card_id: row.ids[0],
                    deck_id: Some(row.ids[1]),
                    note_id: Some(row.ids[2]),
                    preset_id: Some(row.ids[3]),
                    is_query: row.skip,
                    ease: None,
                    duration_millis: None,
                    card_type: None,
                    day_offset: None,
                    current_elapsed_days: None,
                    current_elapsed_seconds: None,
                    target_retentions: [None; 4],
                    enforce_grade_order: true,
                };
                let heads = model.review(&row.features, states.state_ref(&input));
                let mut actual = vec![heads.retrievability.clamp(1e-5, 1.0 - 1e-5)];
                actual.extend(heads.button_probabilities);
                actual.push(predict_curve(&heads.curve, row.elapsed));
                actual.extend(
                    user.sweep
                        .iter()
                        .map(|&elapsed| predict_curve(&heads.curve, elapsed)),
                );
                let expected = if format == "f32" {
                    &row.fp32
                } else {
                    &row.int8
                };
                for (head, (&a, &b)) in actual.iter().zip(expected).enumerate() {
                    maximum = maximum.max((a - b).abs());
                    assert!(
                        (a - b).abs() <= 1e-5,
                        "{} {format} row {index} head {head}: {a} != {b}",
                        user.name
                    );
                }
                if !row.skip {
                    states.store(&input, heads.next_state);
                }
            }
        }
        println!(
            "{package} {format} published vectors: maximum absolute probability error {maximum}"
        );
    }
}

pub fn verify_all_published_vectors() {
    for (name, bytes) in [
        ("sm40", &include_bytes!("testdata/sm40-vectors.json.gz")[..]),
        ("sm36", &include_bytes!("testdata/sm36-vectors.json.gz")[..]),
        ("sm55", &include_bytes!("testdata/sm55-vectors.json.gz")[..]),
        ("sm56", &include_bytes!("testdata/sm56-vectors.json.gz")[..]),
    ] {
        let mut data = Vec::new();
        flate2::read::GzDecoder::new(bytes)
            .read_to_end(&mut data)
            .unwrap();
        check_published_vectors(name, &data);
    }
}
