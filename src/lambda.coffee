import * as Time from "@dashkite/joy/time"
import FS from "fs/promises"

import { 
  guard
  nameLambda
  nameRole
} from "./helpers"

import {
  publishLambda
  versionLambda
  deleteLambda
  putSources
  deleteSources
} from "@dashkite/dolores/lambda"

import {
  getStream
} from "@dashkite/dolores/kinesis"

import { 
  getRoleARN
  deleteRole
} from "@dashkite/dolores/roles"


updateLambdas = ({ namespace, environment, lambda, variables, version }) ->

  for handler in lambda?.handlers ? []
    
    try
      # if there's no zip file, the file hasn't changed
      data = await FS.readFile "build/lambda/#{ handler.name }.zip"
    
    if data?
      console.log "publishing #{ handler.name }"

      name = nameLambda { namespace, environment, name: handler.name }

      role = await getRoleARN "#{name}-role"

      await publishLambda name, data, {
        handler: "#{ handler.name }.handler"
        handler.configuration...
        environment: { environment, variables... }
        role
      }

      # Lambda needs to exist before we link it to its sources.
      if handler.sources?
        await putSources name, handler.sources

      if version
        { version } = await versionLambda name
        console.log "cut version #{ name } v#{ version }"

updateSources = ({ namespace, environment, handler }) ->
  name = nameLambda { namespace, environment, name: handler.name }
  sources = []
  for source in handler.sources
    switch source.type
      when "kinesis"
        stream = await getStream source.name
        if !stream?
          throw new Error "stream #{source.name} is not available"
        sources.push
          BatchSize: source.batchSize ? 1
          Enabled: true
          EventSourceArn: stream.arn
          FunctionName: name
          StartingPosition: "LATEST"

          # "TRIM_HORIZON" - Send everything that's available, which can be thousands
          # "AT_TIMESTAMP" - From a timestamp specified in another field
          # "LATEST" - Start listening now
      
      else
        throw new Error "unknown stream type"

  await putSources name, sources


export default (genie, options) ->

  if options.lambda?
    { namespace, lambda, variables } = options

    genie.define "sky:lambda:update",
      [ 
        "clean"
        "sky:roles:publish:*"
        "sky:zip:*" 
      ],
      guard (environment) ->
        updateLambdas {
          namespace
          environment
          lambda
          variables
          version: false 
        }

    genie.define "sky:lambda:publish",
      [ 
        "clean"
        "sky:roles:publish:*"
        "sky:zip:*" 
      ],
      guard (environment) ->
        updateLambdas {
          namespace
          environment
          lambda
          variables
          version: true
        }

    genie.define "sky:lambda:version", guard (environment, name) ->
      versionLambda nameLambda { namespace, environment, name }

    genie.define "sky:lambda:delete", guard (environment, name) ->
      await deleteLambda nameLambda { namespace, environment, name }
      await deleteSources nameLambda { namespace, environment, name }
      await deleteRole nameRole { namespace, environment, name }