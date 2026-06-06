require "open3"
require "tempfile"

# Identifies a Yu-Gi-Oh card from a photo: OCR the image with Tesseract, then
# fuzzy-match the extracted text against the catalog using Postgres pg_trgm
# similarity. Mirrors the "Vision" idea of card-data APIs in a self-hosted way.
class CardScanner
  THRESHOLD = 0.4
  TESSERACT_CANDIDATES = ["/opt/homebrew/bin/tesseract", "/usr/local/bin/tesseract", "tesseract"].freeze
  VIPS_CANDIDATES = ["/opt/homebrew/bin/vips", "/usr/local/bin/vips", "vips"].freeze
  VIPSHEADER_CANDIDATES = ["/opt/homebrew/bin/vipsheader", "/usr/local/bin/vipsheader", "vipsheader"].freeze

  Result = Struct.new(:card, :score, :raw_text, :counters_for, :key_card_of, :error, keyword_init: true) do
    def matched? = card.present?
  end

  def initialize(logger: Rails.logger)
    @logger = logger
  end

  def identify(image_path)
    text = run_ocr(image_path)
    return Result.new(error: "Could not read text from the image.", raw_text: "") if text.blank?

    card, score = best_match(text)
    return Result.new(raw_text: text, score: score) unless card

    Result.new(
      card: card,
      score: score,
      raw_text: text,
      counters_for: decks_countered_by(card),
      key_card_of: decks_keyed_on(card)
    )
  rescue => e
    @logger.error("[CardScanner] #{e.class}: #{e.message}")
    Result.new(error: "Scan failed: #{e.message}")
  end

  private

  # OCR the cropped top "name band" (high accuracy on straight-on cards) AND the
  # full image (covers off-angle photos), then match across both.
  def run_ocr(image_path)
    raise "Tesseract not installed" unless tesseract_bin

    band = name_band_text(image_path)
    full = ocr_bytes(downscaled_for_ocr(image_path), psm: "6")
    [band, full].reject(&:blank?).join("\n").force_encoding("UTF-8").scrub
  end

  # Tesseract runtime is roughly linear in pixel count; raw phone photos are
  # 3-4k px wide and take 30s+ on a 1GB box. Downscale the full image to a sane
  # width before the full-image OCR pass (the name-band pass keeps full detail
  # for the title, this fallback only needs to read body text on off-angle shots).
  def downscaled_for_ocr(image_path, max_w: 1400)
    vbin = vips_bin
    hbin = vipsheader_bin
    return File.binread(image_path) unless vbin && hbin

    width = capture_int(hbin, "-f", "width", image_path)
    return File.binread(image_path) if width.zero? || width <= max_w

    tmp = Tempfile.new(["cd_full", ".png"])
    tmp.close
    _o, _e, st = Open3.capture3(vbin, "thumbnail", image_path, tmp.path, max_w.to_s)
    st.success? ? File.binread(tmp.path) : File.binread(image_path)
  rescue => e
    @logger.warn("[CardScanner] downscale failed: #{e.message}")
    File.binread(image_path)
  ensure
    tmp&.unlink
  end

  # Pipe bytes to tesseract via STDIN (the binary cannot always fopen arbitrary
  # temp paths under sandboxing; stdin sidesteps that entirely).
  def ocr_bytes(bytes, psm:)
    stdout, stderr, status = Open3.capture3(
      tesseract_bin, "stdin", "stdout", "--psm", psm, stdin_data: bytes, binmode: true
    )
    @logger.warn("[CardScanner] tesseract stderr: #{stderr}") unless status.success?
    stdout.to_s
  end

  # Crop the top name band proportionally and OCR it as a single line (psm 7).
  def name_band_text(image_path)
    vbin = vips_bin
    hbin = vipsheader_bin
    return "" unless vbin && hbin

    width = capture_int(hbin, "-f", "width", image_path)
    height = capture_int(hbin, "-f", "height", image_path)
    return "" if width.zero? || height.zero?

    left = (width * 0.04).to_i
    top = (height * 0.045).to_i
    crop_w = (width * 0.82).to_i
    crop_h = (height * 0.085).to_i

    tmp = Tempfile.new(["cd_band", ".png"])
    tmp.close
    _out, _err, status = Open3.capture3(vbin, "crop", image_path, tmp.path, left.to_s, top.to_s, crop_w.to_s, crop_h.to_s)
    return "" unless status.success?

    # Upscale 3x so the small title text is large enough for accurate OCR.
    big = Tempfile.new(["cd_band3x", ".png"])
    big.close
    _o2, _e2, st2 = Open3.capture3(vbin, "resize", tmp.path, big.path, "3")
    band_path = st2.success? ? big.path : tmp.path

    ocr_bytes(File.binread(band_path), psm: "7")
  rescue => e
    @logger.warn("[CardScanner] name-band crop failed: #{e.message}")
    ""
  ensure
    tmp&.unlink
    big&.unlink
  end

  def capture_int(*cmd)
    out, _err, status = Open3.capture3(*cmd)
    status.success? ? out.to_s.strip.to_i : 0
  rescue
    0
  end

  def tesseract_bin
    @tesseract_bin ||= resolve_bin(TESSERACT_CANDIDATES)
  end

  def vips_bin
    @vips_bin ||= resolve_bin(VIPS_CANDIDATES)
  end

  def vipsheader_bin
    @vipsheader_bin ||= resolve_bin(VIPSHEADER_CANDIDATES)
  end

  def resolve_bin(candidates)
    candidates.find { |c| c.include?("/") ? File.executable?(c) : which(c) }
  end

  def which(cmd)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |p| File.executable?(File.join(p, cmd)) }
  end

  # Try the full cleaned text and each line; keep the highest-scoring match.
  def best_match(text)
    queries = candidate_queries(text)
    best_card = nil
    best_score = 0.0

    queries.each do |q|
      card, score = match_one(q)
      if card && score > best_score
        best_card = card
        best_score = score
      end
    end

    best_score >= THRESHOLD ? [best_card, best_score.round(3)] : [nil, best_score.round(3)]
  end

  # Match every readable line plus the first-two-lines joined (card names can
  # wrap). The threshold filters out noise so we never assert a wrong card.
  def candidate_queries(text)
    lines = text.split("\n")
                .map { |l| l.gsub(/[^A-Za-z0-9 &"'\-.!]/, " ").squish }
                .select { |l| l.length >= 4 }

    joined = lines.first(2).join(" ")
    (lines + [joined]).reject(&:blank?).uniq.first(20)
  end

  def match_one(query)
    quoted = ActiveRecord::Base.connection.quote(query)
    row = Card.select(Arel.sql("cards.*, similarity(name, #{quoted}) AS sim"))
              .order(Arel.sql("sim DESC"))
              .limit(1)
              .first
    row ? [row, row.sim.to_f] : nil
  end

  def decks_countered_by(card)
    Deck.joins(:counter_recommendations)
        .where(counter_recommendations: { card_id: card.id })
        .where.not(counter_recommendations: { category: CounterRecommendation::KEY_CARD })
        .distinct
  end

  def decks_keyed_on(card)
    Deck.joins(:counter_recommendations)
        .where(counter_recommendations: { card_id: card.id, category: CounterRecommendation::KEY_CARD })
        .distinct
  end
end
