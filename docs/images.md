# Images

`Zaniah::Image` accepts PNG, GIF, and baseline JPEG data. Paths are read as
bytes, then the format is selected from its signature; use `from_bytes` when
the application already has the encoded data:

```ruby
image = Zaniah::Image.from_bytes(File.binread("photo.jpg"))
explicit = Zaniah::Image.from_bytes(bytes, format: :jpeg)
```

JPEG decoding is pure Ruby and returns RGBA pixels. It supports 8-bit baseline
grayscale, RGB (Adobe transform 0), and YCbCr, including JFIF frame dimensions,
Exif orientation 1–8, and 4:4:4, 4:2:2, and 4:2:0 sampling. Progressive,
extended, arithmetic-coded, CMYK, and multi-scan JPEGs are not supported;
unsupported coding processes raise `Zaniah::JPEG::Error` instead of producing
an incomplete image. `JPEG.decode` limits images to 16,777,216 pixels by
default and accepts a different positive `max_pixels` limit explicitly.
