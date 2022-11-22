import { spawn } from "child_process"
import { createServer } from "http"

export const baseUrl = "http://127.0.0.1:7676"
export var lastBackendRequest

var backend
var fastlyProcess

export async function startBackend() {
  backend = createServer((req, res) => {
    lastBackendRequest = req
    res.writeHead(200)
    res.end()
  })
  await new Promise(resolve => backend.listen(8080, undefined, undefined, resolve))
}

export async function stopBackend() {
  await new Promise(resolve => backend.close(resolve))
}

export async function startFastly() {
  console.log("Starting Fastly development server...")
  fastlyProcess = spawn("fastly", ["compute", "serve"])
  await new Promise((resolve, reject) => {
    fastlyProcess.addListener("exit", code => {
      fastlyProcess = null
      reject(new Error(`Fastly development server exited unexpectedly with code ${code}`))
    })
    fastlyProcess.stdout.addListener("data", data => {
      if (data.toString().includes(`Listening on ${baseUrl}`)) {
        resolve()
      }
    })
  })
  fastlyProcess.removeAllListeners()
  fastlyProcess.stdout.removeAllListeners()
}

export async function stopFastly() {
  if (fastlyProcess !== null) {
    fastlyProcess.kill('SIGINT')
    const code = await new Promise(resolve => fastlyProcess.on('exit', resolve))
    console.log(`\nFastly development server exited with code ${code}`)
  }
}
