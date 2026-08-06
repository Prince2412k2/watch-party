import './styles.css'
// The generated analog token layer (`:root { --an-* }`). Consumed by the player
// control kit; see app/shared/design/README.md.
import './design/analog.css'
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.tsx'

const root = document.getElementById('root')
if (!root) throw new Error('Missing root element')

ReactDOM.createRoot(root).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
