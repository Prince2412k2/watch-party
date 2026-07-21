// Typed wrapper around the vendored Guacamole keyboard (guacamoleKeyboardCore.ts),
// ported from neko/client/src/utils/guacamole-keyboard.ts.
import GuacamoleKeyboard from './guacamoleKeyboardCore'

export interface GuacamoleKeyboardInterface {
  /**
   * Fired whenever the user presses a key with the element associated
   * with this Guacamole.Keyboard in focus.
   *
   * @param keysym The keysym of the key being pressed.
   * @return true if the key event should be allowed through to the
   *         browser, false otherwise.
   */
  onkeydown?: (keysym: number) => boolean

  /**
   * Fired whenever the user releases a key with the element associated
   * with this Guacamole.Keyboard in focus.
   *
   * @param keysym The keysym of the key being released.
   */
  onkeyup?: (keysym: number) => void

  /** Marks a key as pressed, firing the keydown event if registered. */
  press: (keysym: number) => boolean

  /** Marks a key as released, firing the keyup event if registered. */
  release: (keysym: number) => void

  /** Presses and releases the keys necessary to type the given string of text. */
  type: (str: string) => void

  /** Resets the state of this keyboard, releasing all keys, and firing keyup events for each. */
  reset: () => void

  /**
   * Attaches event listeners to the given Element, automatically translating
   * received key, input, and composition events into simple keydown/keyup
   * events signalled through onkeydown and onkeyup.
   */
  listenTo: (element: Element | Document) => void
}

export default function createGuacamoleKeyboard(element?: Element): GuacamoleKeyboardInterface {
  const Keyboard = {}

  GuacamoleKeyboard.bind(Keyboard, element)()

  return Keyboard as GuacamoleKeyboardInterface
}
