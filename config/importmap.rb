# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "sortablejs" # vendored at vendor/javascript/sortablejs.js (no CDN/CSP dependency)
pin_all_from "app/javascript/controllers", under: "controllers"
