import express from 'express'
import { createServer } from 'http'
import { Server } from 'socket.io'
import cookieParser from 'cookie-parser'
import session from 'express-session'

const app = express()
const httpServer = createServer(app)
const io = new Server(httpServer, { cors: { origin: 'http://localhost:5173', credentials: true } })

app.use(express.json())
app.use(cookieParser())
app.use(session({
  secret: process.env.SESSION_SECRET || 'changeme',
  resave: false,
  saveUninitialized: false,
  cookie: { httpOnly: true, sameSite: 'lax' },
}))

app.get('/api/health', (_req, res) => res.json({ ok: true }))

io.on('connection', (socket) => {
  console.log('socket connected', socket.id)
  socket.on('disconnect', () => console.log('socket disconnected', socket.id))
})

const PORT = process.env.PORT || 3000
httpServer.listen(PORT, () => console.log(`server listening on :${PORT}`))
