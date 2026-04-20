"""
Download GloVe 6B 50d word vectors from Stanford and extract a curated subset
for use in the game's NLP similarity scoring.

Output: source/word_vectors.bin — a compact binary file that gets #load'd into the game.

Binary format:
  - 4 bytes: num_words (little-endian u32)
  - 4 bytes: num_dims (little-endian u32)
  - For each word:
      - 1 byte: word length
      - N bytes: word (ASCII, lowercase)
      - num_dims * 4 bytes: vector components (little-endian f32)

Usage: python scripts/build_word_vectors.py
"""

import os
import io
import struct
import urllib.request
import zipfile

GLOVE_URL = "https://nlp.stanford.edu/data/glove.6B.zip"
GLOVE_FILE = "glove.6B.50d.txt"
CACHE_DIR = os.path.join(os.path.dirname(__file__), ".cache")
OUTPUT_PATH = os.path.join(os.path.dirname(__file__), "..", "source", "word_vectors.bin")

# How many of the most common words to keep
TOP_N = 5000

# Extra words to always include (game-specific vocabulary)
GAME_WORDS = {
    # game-specific
    "compress", "compressed", "compressing", "compression",
    "tablet", "tablets", "stone", "message", "messages",
    "ship", "shipping", "overseas", "paper", "important",
    "signal", "preserve", "meaning", "information", "loss",
    "world", "figure", "figured", "charge", "save", "saving",
    "company", "millions", "year", "years", "boat",
    "fit", "single", "longer", "sent", "still",
    "space", "empty", "compact", "trick", "basic",
    "due", "diligence", "compacting",
    # common words that GloVe ranks surprisingly low
    "hello", "goodbye", "cat", "feline", "dog", "rug", "mat",
    "moon", "jumps", "jumped", "fox",
}


def download_glove():
    """Download and cache the GloVe zip file."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    zip_path = os.path.join(CACHE_DIR, "glove.6B.zip")

    if os.path.exists(zip_path):
        print(f"Using cached {zip_path}")
        return zip_path

    print(f"Downloading GloVe 6B from {GLOVE_URL}...")
    print("(This is ~862MB, only needed once)")
    urllib.request.urlretrieve(GLOVE_URL, zip_path, reporthook=_progress)
    print("\nDownload complete.")
    return zip_path


def _progress(block_num, block_size, total_size):
    downloaded = block_num * block_size
    pct = min(100, downloaded * 100 // total_size) if total_size > 0 else 0
    mb = downloaded / (1024 * 1024)
    total_mb = total_size / (1024 * 1024)
    print(f"\r  {mb:.0f}/{total_mb:.0f} MB ({pct}%)", end="", flush=True)


def extract_vectors(zip_path):
    """Read the 50d vectors from the zip, return dict of word -> list[float]."""
    print(f"Extracting {GLOVE_FILE} from zip...")
    vectors = {}
    rank = 0

    with zipfile.ZipFile(zip_path) as zf:
        with zf.open(GLOVE_FILE) as f:
            for line in io.TextIOWrapper(f, encoding="utf-8"):
                parts = line.strip().split()
                word = parts[0]
                rank += 1

                # Keep top N words by rank (GloVe is sorted by frequency)
                # plus any game-specific words
                if rank <= TOP_N or word in GAME_WORDS:
                    vec = [float(x) for x in parts[1:]]
                    vectors[word] = vec

    print(f"Extracted {len(vectors)} words ({TOP_N} common + game vocabulary)")
    return vectors


def write_binary(vectors, path):
    """Write vectors to compact binary format."""
    words = sorted(vectors.keys())
    num_dims = len(next(iter(vectors.values())))

    with open(path, "wb") as f:
        f.write(struct.pack("<II", len(words), num_dims))

        for word in words:
            word_bytes = word.encode("ascii", errors="replace")
            if len(word_bytes) > 255:
                word_bytes = word_bytes[:255]
            f.write(struct.pack("B", len(word_bytes)))
            f.write(word_bytes)
            for val in vectors[word]:
                f.write(struct.pack("<f", val))

    size_kb = os.path.getsize(path) / 1024
    print(f"Wrote {path} ({size_kb:.0f} KB, {len(words)} words x {num_dims}d)")


def main():
    zip_path = download_glove()
    vectors = extract_vectors(zip_path)
    write_binary(vectors, OUTPUT_PATH)
    print("Done! Rebuild the game to pick up the new vectors.")


if __name__ == "__main__":
    main()
