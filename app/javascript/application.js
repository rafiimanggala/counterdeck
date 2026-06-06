// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Robustness: if a Turbo Frame request ever returns a response without the
// matching frame (e.g. a 5xx error page while the server restarts during a
// deploy), don't leave the frame stuck showing "Content missing" - recover by
// doing a full-page visit with that response so the user is never stranded.
document.addEventListener("turbo:frame-missing", (event) => {
  const { response, visit } = event.detail
  event.preventDefault()
  visit(response)
})
