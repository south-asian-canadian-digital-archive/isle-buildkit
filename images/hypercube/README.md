# Hypercube

Docker image for [Hypercube]. Tesseract as a microservice

Images are normalised with libvips before Tesseract sees them, because
leptonica (Tesseract's image reader) cannot open tiled TIFFs (including every
pyramid TIFF), 16-bit JPEG 2000, float or LAB TIFFs, or HEIF/AVIF. Each page
is auto-rotated from EXIF, colour managed, flattened onto white, converted to
8-bit greyscale and shrunk to at most `HYPERCUBE_MAX_PIXELS` pixels. A
multi-page TIFF is OCR'd page by page; a pyramid TIFF only at full resolution.
PDFs are unchanged (`pdftotext`).

## Settings

| Environment Variable   | Default  | Description                                           |
| :--------------------- | :------- | :---------------------------------------------------- |
| `HYPERCUBE_MAX_PIXELS` | 50000000 | Larger images are downscaled to this many pixels first |

Built from [Islandora-DevOps/isle-buildkit hypercube](https://github.com/Islandora-DevOps/isle-buildkit/tree/main/images/hypercube)

## Dependencies

Requires `islandora/scyllaridae` Docker image to build. Please refer to the
[Scyllaridae Image README](../scyllaridae/README.md) for additional information including
additional settings, volumes, ports, etc.
