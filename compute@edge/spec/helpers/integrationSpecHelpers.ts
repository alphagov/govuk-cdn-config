import { ChildProcessWithoutNullStreams, spawn } from "child_process"
import { createServer, IncomingMessage, Server } from "http"
import assert from "node:assert"

export const baseUrl = "http://127.0.0.1:7676"
export var lastBackendRequest: IncomingMessage | null = null

var backend: Server | null = null
var fastlyProcess: ChildProcessWithoutNullStreams | null = null

export async function startBackend() {
  backend = createServer((req, res) => {
    lastBackendRequest = req
    res.writeHead(200)
    res.end()
  })
  await new Promise(resolve => {
    assert(backend !== null)
    backend.listen(3000, undefined, undefined, () => resolve(undefined))
  })
}

export async function stopBackend() {
  await new Promise(resolve => {
    assert(backend !== null)
    backend.close(resolve)
  })
}

export async function startFastly() {
  console.log("Starting Fastly development server...")
  fastlyProcess = spawn("fastly", ["compute", "serve"])
  await new Promise((resolve, reject) => {
    assert(fastlyProcess !== null)
    fastlyProcess.addListener("exit", (code: any) => {
      fastlyProcess = null
      reject(new Error(`Fastly development server exited unexpectedly with code ${code}`))
    })
    fastlyProcess.stdout.addListener("data", (data: { toString: () => string | string[] }) => {
      if (data.toString().includes(`Listening on ${baseUrl}`)) {
        resolve(undefined)
      }
    })
  })
  fastlyProcess.removeAllListeners()
  fastlyProcess.stdout.removeAllListeners()
}

export async function stopFastly() {
  if (fastlyProcess !== null) {
    fastlyProcess.kill('SIGINT')
    const code = await new Promise(resolve => {
      assert(fastlyProcess !== null)
      fastlyProcess.on('exit', resolve)
    })
    console.log(`\nFastly development server exited with code ${code}`)
  }
}
