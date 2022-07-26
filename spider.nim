import std/parseopt
import strformat
import strutils
import json
import os

proc printBanner() =

  echo """
 _____     _   _         _____ _
|   __|___|_|_| |___ ___|   | |_|_____
|__   | . | | . | -_|  _| | | | |     |
|_____|  _|_|___|___|_| |_|___|_|_|_|_|
      |_|
  """

proc printHelp() =

  echo """
  --json/-j <file>      Nim compilation configuration file
  --debug/-d            Output Debug content
  --spiderpic/-sp       Path to the SpiderPIC binary
                        Per default, the binary is expected to be
                        in the PATH
  """

proc handleStatus(status: int) =
  if status != 0:
    echo "[-] An error occured executing the last command"
    quit()

# The struct for the compilation config
# of nim
type
  config = object
    cacheVersion: string
    outputFile: string
    compile: seq[seq[string]]
    link: seq[string]
    linkcmd: string
    extraCmds: seq[string]
    configFiles: seq[string]
    stdinInput: bool
    projectIsCmd: bool
    cmdInput: string
    currentDir: string
    cmdline: string
    depfiles: seq[string]
    nimexe: string

let
  params = commandLineParams()
  currDirBackup = getCurrentDir()

var
  p = initOptParser(params)
  lastOption = ""
  enableDebug = false
  jsonConfigFile = ""
  spiderPicPath = "SpiderPIC" # default, use spiderpic from PATH


if len(params) == 0:
  printBanner()
  printHelp()
  quit()


for kind, key, val in p.getopt():
  case kind
  of cmdArgument:
    if lastOption == "json" or lastOption == "j":
      jsonConfigFile = key
    elif lastOption.toLower() == "spiderpic" or lastOption.toLower() == "sp":
      if not key.fileExists:
        echo "[-] Supplied SpiderPIC binary does not exist"
        quit()
      else:
        spiderPicPath = key
  of cmdLongOption, cmdShortOption:
    case key
    of "help", "h":
      printHelp()
      quit()
    of "debug", "d":
      enableDebug = true
    lastOption = key
  of cmdEnd: assert(false) # cannot happen


if jsonConfigFile == "" or not jsonConfigFile.fileExists():
  echo "[-] Json file does not exist"
  quit()


let jsonCfg = jsonConfigFile.readFile()
var cfg: config
var exitCode: int

try:
  cfg = to(parseJson(jsonCfg), config)
except:
  echo "[-] Json configuration file parsing error - check the json file"
  quit()


# --- real stuff starts here


printBanner()

os.setCurrentDir(cfg.currentDir)

echo "[*] Compiling C files - including ASM Output -"

# Step 1) Compile all things, having asm output
for c in cfg.compile:
  var compCmd = fmt"{c[1]} -S -masm=intel"
  compCmd = compCmd.replace(".c.o ", ".s ")
  #let compCmd = fmt"i686-w64-mingw32-{c[1]} -S -masm=intel"
  if enableDebug:
    echo "[*] Executing Command:"
    echo &"\t{compCmd}"
  exitCode = execShellCmd(compCmd)
  handleStatus(exitCode)



#quit()
echo "[*] Running SpiderPIC"


for asmF in cfg.compile:
  let asmFile = asmF[0].replace(".nim.c", ".nim.s")
  var spicCmd = fmt"{spiderPicPath} -asm {asmFile} -o {asmFile} -silent"

  echo &"\tObfuscating: {asmF[0]}"

  if enableDebug:
    echo "[*] Executing Command:"
    echo &"\t{spicCmd}"
  exitCode = execShellCmd(spicCmd)
  handleStatus(exitCode)

echo "[*] Compiling C files - To Object"

for c in cfg.compile:
  var compCmd = fmt"{c[1]} -masm=intel"
  compCmd = compCmd.replace(".nim.c", ".nim.s")
  compCmd = compCmd.replace(".nim.s.o", ".nim.c.o")

  if enableDebug:
    echo "[*] Executing Command:"
    echo &"\t{compCmd}"

  exitCode = execShellCmd(compCmd)
  handleStatus(exitCode)

echo "[*] Linking ASM Files"

let linkerCmd = fmt"{cfg.linkcmd}"

if enableDebug:
  echo "[*] Executing Command:"
  echo &"\t{linkerCmd}"

exitCode = execShellCmd(linkerCmd)
handleStatus(exitCode)

echo "[+] Done"

# restore cwd (just in case)
setCurrentDir(currDirBackup)
