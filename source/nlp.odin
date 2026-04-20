package game

import "core:math"
import "core:strings"

EMBEDDING_DIMS :: 50

// Loaded at compile time from the binary built by scripts/build_word_vectors.py
WORD_VECTORS_DATA :: #load("word_vectors.bin")

// Parse header from the baked binary.
wv_num_words :: proc() -> int {
	data := WORD_VECTORS_DATA
	if len(data) < 8 {return 0}
	return int(u32(data[0]) | u32(data[1]) << 8 | u32(data[2]) << 16 | u32(data[3]) << 24)
}

// Read a little-endian f32 from raw bytes.
read_f32 :: proc(data: []u8, offset: int) -> f32 {
	bits :=
		u32(data[offset]) |
		u32(data[offset + 1]) << 8 |
		u32(data[offset + 2]) << 16 |
		u32(data[offset + 3]) << 24
	return transmute(f32)bits
}

// Look up the vector for a word by scanning the binary data.
// Returns a slice into the raw data, or an empty slice if not found.
find_word_vector :: proc(target: string) -> (vec: [EMBEDDING_DIMS]f32, found: bool) {
	data := WORD_VECTORS_DATA
	if len(data) < 8 {return}

	num_words := wv_num_words()
	offset := 8

	for _ in 0 ..< num_words {
		if offset >= len(data) {break}

		word_len := int(data[offset])
		offset += 1
		if offset + word_len > len(data) {break}

		word := string(data[offset:][:word_len])
		offset += word_len

		vec_start := offset
		offset += EMBEDDING_DIMS * 4
		if offset > len(data) {break}

		if word == target {
			for d in 0 ..< EMBEDDING_DIMS {
				vec[d] = read_f32(data, vec_start + d * 4)
			}
			return vec, true
		}
	}

	return {}, false
}

// Compute sentence embedding by averaging word vectors.
sentence_embedding :: proc(text: string) -> (result: [EMBEDDING_DIMS]f32, count: int) {
	word_start := -1
	for i := 0; i <= len(text); i += 1 {
		c := i < len(text) ? text[i] : 0
		if is_word_char(c) {
			if word_start < 0 {
				word_start = i
			}
		} else if word_start >= 0 {
			word := strings.to_lower(text[word_start:i], context.temp_allocator)
			vec, found := find_word_vector(word)
			if found {
				for d in 0 ..< EMBEDDING_DIMS {
					result[d] += vec[d]
				}
				count += 1
			}
			word_start = -1
		}
	}

	if count > 0 {
		for d in 0 ..< EMBEDDING_DIMS {
			result[d] /= f32(count)
		}
	}

	return
}

// Cosine similarity between two embedding vectors.
cosine_sim :: proc(a, b: [EMBEDDING_DIMS]f32) -> f64 {
	dot: f64 = 0
	mag_a: f64 = 0
	mag_b: f64 = 0
	for d in 0 ..< EMBEDDING_DIMS {
		dot += f64(a[d]) * f64(b[d])
		mag_a += f64(a[d]) * f64(a[d])
		mag_b += f64(b[d]) * f64(b[d])
	}
	if mag_a < 1e-10 || mag_b < 1e-10 {
		return 0
	}
	return dot / (math.sqrt(mag_a) * math.sqrt(mag_b))
}

// Compute semantic similarity between two strings using GloVe word embeddings.
// Returns 0.0 (completely different) to 1.0 (identical meaning).
compute_similarity :: proc(original: string, compressed: string) -> f64 {
	if len(original) == 0 && len(compressed) == 0 {
		return 1.0
	}
	if len(original) == 0 || len(compressed) == 0 {
		return 0.0
	}

	emb_a, count_a := sentence_embedding(original)
	emb_b, count_b := sentence_embedding(compressed)

	if count_a == 0 || count_b == 0 {
		return 0.0
	}

	return clamp(cosine_sim(emb_a, emb_b), 0, 1)
}

is_word_char :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '\''
}
