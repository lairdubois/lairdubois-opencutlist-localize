# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/lib", under: "lib"
# CodeMirror : jsDelivr minified builds (dist/index.min.js) of these versions
pin "@codemirror/commands", to: "@codemirror--commands.js" # @6.11.1
pin "@codemirror/state", to: "@codemirror--state.js" # @6.7.6
pin "@codemirror/view", to: "@codemirror--view.js" # @6.43.14
pin "@codemirror/language", to: "@codemirror--language.js" # @6.13.1
pin "@codemirror/streamparser", to: "@codemirror--streamparser.js" # @6.0.0
pin "@lezer/common", to: "@lezer--common.js" # @1.5.3
pin "@lezer/highlight", to: "@lezer--highlight.js" # @1.2.5
pin "@marijn/find-cluster-break", to: "@marijn--find-cluster-break.js" # @1.0.4
pin "crelt" # @1.0.7
pin "style-mod" # @4.1.4
pin "w3c-keyname" # @2.2.8
