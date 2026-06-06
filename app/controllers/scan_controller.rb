# Card scanner: upload a photo of a physical card -> identify it -> jump to
# any decks it counters. OCR logic lives in CardScanner (P8).
class ScanController < ApplicationController
  def show
    @result = nil
  end

  def create
    if params[:image].blank?
      redirect_to scan_path, alert: "Choose an image first." and return
    end

    @result = CardScanner.new.identify(params[:image].tempfile.path)
    render :show
  end
end
