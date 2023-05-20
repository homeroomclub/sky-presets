import { guard } from "./helpers"

import {
  getQueueURL
  getQueueARN
  putQueue
  emptyQueue
  deleteQueue
} from "@dashkite/dolores/queue"

export default ( genie, options ) ->
  if options.queues?
    { queues } = options

    setupDeadLetterQueue = ( queue, options ) ->
      if queue.name.endsWith ".fifo"
        name = queue.name.replace /\.fifo$/, "-dlq.fifo"
      else
        name = queue.name + "-dlq"
      
      await putQueue name, options
      name

    setupQueue = ( queue ) ->
      # We always use queue encryption
      options =
        SqsManagedSseEnabled: true

      if queue.retention?
        options.MessageRetentionPeriod = queue.retention
      if queue.visibilityTimeout?
        options.VisibilityTimeout = queue.visibilityTimeout
      
      dlqName = await setupDeadLetterQueue queue, options
      options.RedrivePolicy = JSON.stringify await do ->
        deadLetterTargetArn: await getQueueARN dlqName
        maxReceiveCount: queue.retries ? 5
      
      await putQueue queue.name, options

    genie.define "sky:queues:check", ->
      missing = []
      for queue in queues
        if !( await getQueueURL queue.name )
          missing.push queue.name
      if missing.length == 0
        console.log "All queues are available."
      else
        for name in missing
          console.warn "Queue [ #{name} ] does not exist or is unavailable"
        throw new Error "queues:check failed"

    genie.define "sky:queues:put", ->
      for queue in queues
        await setupQueue queue

    genie.define "sky:queue:empty", guard ( name ) ->
      if await getQueueURL name
        await emptyQueue name
      else
        throw new Error "queue [ #{name} ] does not exist"

    genie.define "sky:queue:delete", guard ( name ) ->
      if await getQueueURL name
        await emptyQueue name
        await deleteQueue name
        console.log "Expect this operation to take another 60 seconds to complete."
      else
        throw new Error "queue [ #{name} ] does not exist"