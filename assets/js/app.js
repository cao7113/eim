// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/eim"
import topbar from "../vendor/topbar"

if (process.env.NODE_ENV === "development" && window.location.pathname === "/sign-in") {
  const fillDevCredentials = () => {
    if (window.location.pathname !== "/sign-in") {
      observer.disconnect()
      document.removeEventListener("input", stopFilling, true)
      return
    }

    const email = document.querySelector('form input[type="email"]')
    const form = email?.closest("form")
    const password = form?.querySelector('input[type="password"]')

    if (email && !email.value) email.value = "dev@l.h"
    if (password && !password.value) password.value = "password123456"
  }
  const stopFilling = () => {
    observer.disconnect()
    document.removeEventListener("input", stopFilling, true)
  }
  const observer = new MutationObserver(fillDevCredentials)

  observer.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["value"],
    childList: true,
    subtree: true,
  })
  document.addEventListener("input", stopFilling, true)
  fillDevCredentials()
}

const closeNavTools = menu => {
  menu.classList.remove("is-open")
  menu.querySelector("button[aria-controls]").setAttribute("aria-expanded", "false")
}

document.addEventListener("click", event => {
  const toggle = event.target.closest(".nav-tools > button[aria-controls]")
  if (!toggle) return

  const menu = toggle.parentElement
  menu.classList.remove("is-dismissed")
  const isOpen = menu.classList.toggle("is-open")
  if (!isOpen) menu.classList.add("is-dismissed")
  toggle.setAttribute("aria-expanded", String(isOpen))
})

document.addEventListener("pointerover", event => {
  const menu = event.target.closest(".nav-tools")
  if (menu && !menu.contains(event.relatedTarget)) {
    menu.classList.remove("is-dismissed")
    menu.querySelector("button[aria-controls]").setAttribute("aria-expanded", "true")
  }
})

document.addEventListener("focusin", event => {
  const menu = event.target.closest(".nav-tools")
  if (menu && !menu.contains(event.relatedTarget)) {
    menu.classList.remove("is-dismissed")
    menu.querySelector("button[aria-controls]").setAttribute("aria-expanded", "true")
  }
})

document.addEventListener("focusout", event => {
  const menu = event.target.closest(".nav-tools")
  if (menu && !menu.contains(event.relatedTarget) && !menu.matches(":hover")) closeNavTools(menu)
})

document.addEventListener("pointerout", event => {
  const menu = event.target.closest(".nav-tools")
  if (!menu || menu.contains(event.relatedTarget)) return

  const activeElement = document.activeElement
  const keyboardFocused = activeElement instanceof HTMLElement &&
    menu.contains(activeElement) && activeElement.matches(":focus-visible")
  if (!keyboardFocused) {
    closeNavTools(menu)
    if (activeElement instanceof HTMLElement && menu.contains(activeElement)) activeElement.blur()
  }
})

document.addEventListener("pointerdown", event => {
  document.querySelectorAll(".nav-tools").forEach(menu => {
    if (!menu.contains(event.target)) {
      closeNavTools(menu)
      if (menu.contains(document.activeElement)) document.activeElement.blur()
    }
  })
})

document.addEventListener("keydown", event => {
  if (event.key !== "Escape") return
  const menu = event.target.closest(".nav-tools")
  if (menu) {
    closeNavTools(menu)
    menu.classList.add("is-dismissed")
    menu.querySelector("button[aria-controls]").focus()
  }
})

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
