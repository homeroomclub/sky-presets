import { guard } from "./helpers"

import {
  getQueueARN
} from "@dashkite/dolores/queue"

import {
  getSchedule
  createAccessRole
  putSchedule
  deleteSchedule
} from "@dashkite/dolores/schedule"



export default ( genie, options ) ->
  if options.schedules?
    { schedules } = options

    setupSchedule = ( schedule ) ->
      options =
        Description: schedule.description
        FlexibleTimeWindow: 
          Mode: "OFF"
        GroupName: schedule.group
        Name: schedule.name
        ScheduleExpression: schedule.rate

      if !schedule.enabled? || schedule.enabled == true
        options.State = "ENABLED"
      else
        options.State = "DISABLED"

      accessRole = {}
      switch schedule.target?.type
        when "sqs"
          accessRole = await createAccessRole schedule
          
          options.Target =
            Arn: await getQueueARN schedule.target.name
            Input: JSON.stringify schedule.target.body
            RoleArn:
              "Fn::GetAtt": [ "IAMRole", "Arn" ]

        else
          throw new Error "genie does not currently support scheduled events for this service"

      await putSchedule schedule, accessRole, options



    genie.define "sky:schedules:check", ->
      missing = []
      for schedule in schedules
        if !( await getSchedule schedule )
          missing.push schedule
      if missing.length == 0
        console.log "All schedules are available."
      else
        for schedule in missing
          console.warn "Schedule [ #{schedule.group} #{schedule.name} ] does not exist or is unavailable"
        throw new Error "schedules:check failed"

    genie.define "sky:schedules:put", ->
      for schedule in schedules
        await setupSchedule schedule

    genie.define "sky:schedule:delete", guard ( group, name ) ->
      if await getSchedule { group, name }
        await deleteSchedule { group, name }
      else
        throw new Error "schedule [ #{group} #{name} ] does not exist"

    genie.define "sky:schedules:delete", ->
      for schedule in schedules when await getSchedule schedule
        await deleteSchedule schedule