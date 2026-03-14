from src.claim_processing_function.pipeline.persist import _chunk_pages_without_splitting


def test_chunk_pages_without_splitting_preserves_page_boundaries():
    pages = ["a" * 4000, "b" * 100, "c" * 100]
    chunks = _chunk_pages_without_splitting(pages, max_tokens=1000)
    # first long page remains whole in a single chunk
    assert chunks[0] == pages[0]
