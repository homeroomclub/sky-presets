import {
  getLambdaARN
} from "@dashkite/dolores/lambda"

import {
  createRule
} from "@dashkite/dolores/events"

buildTarget = (name) ->
  arn = await getLambdaARN name
  parts = arn.split ":"
  Arn: parts[0..-2].join ":"
  Id: name

export default (genie, { namespace, bridge, lambda }) ->

  # TODO add delete / teardown

  genie.define "sky:bridge:publish", [ "role:build:*", "sky:lambda:update:*" ], (environment) ->
    { name } = lambda.handlers[0] 
    await createRule {
      name: "#{namespace}-#{environment}-#{bridge.name}-bridge"
      target: await buildTarget "#{namespace}-#{environment}-#{name}-lambda"
      schedule: bridge.schedule
    }    
    