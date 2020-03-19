import Flutter
import UIKit
import EventKit

extension Date {
    var millisecondsSinceEpoch: Double { return self.timeIntervalSince1970 * 1000.0 }
}

extension EKParticipant {
    var emailAddress: String? {
        return self.value(forKey: "emailAddress") as? String
    }
}

public class SwiftDeviceCalendarPlugin: NSObject, FlutterPlugin {
    struct Calendar: Codable {
        let id: String
        let name: String
        let isReadOnly: Bool
        let isDefault: Bool
        let color : Int
    }
    
    struct Event: Codable {
        let eventId: String
        let calendarId: String
        let title: String
        let description: String?
        let start: Int64
        let end: Int64
        let allDay: Bool
        let attendees: [Attendee]
        let location: String?
        let url: String?
        let recurrenceRule: RecurrenceRule?
        let organizer: Attendee?
        let reminders: [Reminder]
    }
    
    struct RecurrenceRule: Codable {
        let recurrenceFrequency: Int
        let totalOccurrences: Int?
        let interval: Int
        let endDate: Int64?
        let daysOfWeek: [Int]?
        let dayOfMonth: Int?
        let monthOfYear: Int?
        let weekOfMonth: Int?
    }
    
    struct Attendee: Codable {
        let name: String?
        let emailAddress: String
        let role: Int
        let attendanceStatus: Int
    }
    
    struct Reminder: Codable {
        let minutes: Int
    }
    
    static let channelName = "plugins.builttoroam.com/device_calendar"
    let notFoundErrorCode = "404"
    let notAllowed = "405"
    let genericError = "500"
    let unauthorizedErrorCode = "401"
    let unauthorizedErrorMessage = "The user has not allowed this application to modify their calendar(s)"
    let calendarNotFoundErrorMessageFormat = "The calendar with the ID %@ could not be found"
    let calendarReadOnlyErrorMessageFormat = "Calendar with ID %@ is read-only"
    let eventNotFoundErrorMessageFormat = "The event with the ID %@ could not be found"
    let eventStore = EKEventStore()
    let requestPermissionsMethod = "requestPermissions"
    let hasPermissionsMethod = "hasPermissions"
    let retrieveCalendarsMethod = "retrieveCalendars"
    let retrieveEventsMethod = "retrieveEvents"
    let createOrUpdateEventMethod = "createOrUpdateEvent"
    let updateEventInstanceMethod = "updateEventInstance"
    let deleteEventMethod = "deleteEvent"
    let deleteEventInstanceMethod = "deleteEventInstance"
    let calendarIdArgument = "calendarId"
    let startDateArgument = "startDate"
    let endDateArgument = "endDate"
    let eventIdArgument = "eventId"
    let eventIdsArgument = "eventIds"
    let eventTitleArgument = "eventTitle"
    let eventDescriptionArgument = "eventDescription"
    let eventAllDayArgument = "eventAllDay"
    let eventStartDateArgument =  "eventStartDate"
    let eventEndDateArgument = "eventEndDate"
    let eventLocationArgument = "eventLocation"
    let eventURLArgument = "eventURL"
    let attendeesArgument = "attendees"
    let recurrenceRuleArgument = "recurrenceRule"
    let recurrenceFrequencyArgument = "recurrenceFrequency"
    let totalOccurrencesArgument = "totalOccurrences"
    let intervalArgument = "interval"
    let daysOfWeekArgument = "daysOfWeek"
    let dayOfMonthArgument = "dayOfMonth"
    let monthOfYearArgument = "monthOfYear"
    let weekOfMonthArgument = "weekOfMonth"
    let nameArgument = "name"
    let emailAddressArgument = "emailAddress"
    let roleArgument = "role"
    let remindersArgument = "reminders"
    let minutesArgument = "minutes"
    let followingInstancesArgument = "followingInstances"
    let validFrequencyTypes = [EKRecurrenceFrequency.daily, EKRecurrenceFrequency.weekly, EKRecurrenceFrequency.monthly, EKRecurrenceFrequency.yearly]
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = SwiftDeviceCalendarPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case requestPermissionsMethod:
            requestPermissions(result)
        case hasPermissionsMethod:
            hasPermissions(result)
        case retrieveCalendarsMethod:
            retrieveCalendars(result)
        case retrieveEventsMethod:
            retrieveEvents(call, result)
        case createOrUpdateEventMethod:
            createOrUpdateEvent(call, result)
        case updateEventInstanceMethod:
            createOrUpdateEvent(call, result)
        case deleteEventMethod:
            deleteEvent(call, result)
        case deleteEventInstanceMethod:
            deleteEvent(call, result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func hasPermissions(_ result: FlutterResult) {
        let hasPermissions = self.hasPermissions()
        result(hasPermissions)
    }
    
    private func retrieveCalendars(_ result: @escaping FlutterResult) {
        checkPermissionsThenExecute(permissionsGrantedAction: {
            let ekCalendars = self.eventStore.calendars(for: .event)
            let defaultCalendar = self.eventStore.defaultCalendarForNewEvents
            var calendars = [Calendar]()
            for ekCalendar in ekCalendars {
                let calendar = Calendar(id: ekCalendar.calendarIdentifier, name: ekCalendar.title, isReadOnly: !ekCalendar.allowsContentModifications, isDefault: defaultCalendar?.calendarIdentifier == ekCalendar.calendarIdentifier,
                                        color: UIColor(cgColor: ekCalendar.cgColor).rgb()!)
                calendars.append(calendar)
            }
            
            self.encodeJsonAndFinish(codable: calendars, result: result)
        }, result: result)
    }
    
    private func retrieveEvents(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        checkPermissionsThenExecute(permissionsGrantedAction: {
            let arguments = call.arguments as! Dictionary<String, AnyObject>
            let calendarId = arguments[calendarIdArgument] as! String
            let startDateMillisecondsSinceEpoch = arguments[startDateArgument] as? NSNumber
            let endDateDateMillisecondsSinceEpoch = arguments[endDateArgument] as? NSNumber
            let eventIds = arguments[eventIdsArgument] as? [String]
            var events = [Event]()
            let specifiedStartEndDates = startDateMillisecondsSinceEpoch != nil && endDateDateMillisecondsSinceEpoch != nil
            if specifiedStartEndDates {
                let startDate = Date (timeIntervalSince1970: startDateMillisecondsSinceEpoch!.doubleValue / 1000.0)
                let endDate = Date (timeIntervalSince1970: endDateDateMillisecondsSinceEpoch!.doubleValue / 1000.0)
                let ekCalendar = self.eventStore.calendar(withIdentifier: calendarId)
                let predicate = self.eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [ekCalendar!])
                let ekEvents = self.eventStore.events(matching: predicate)
                for ekEvent in ekEvents {
                    let event = createEventFromEkEvent(calendarId: calendarId, ekEvent: ekEvent)
                    events.append(event)
                }
            }
            
            if eventIds == nil {
                self.encodeJsonAndFinish(codable: events, result: result)
                return
            }
            
            if specifiedStartEndDates {
                events = events.filter({ (e) -> Bool in
                    e.calendarId == calendarId && eventIds!.contains(e.eventId)
                })
                
                self.encodeJsonAndFinish(codable: events, result: result)
                return
            }
            
            for eventId in eventIds! {
                let ekEvent = self.eventStore.event(withIdentifier: eventId)
                if ekEvent == nil {
                    continue
                }
                
                let event = createEventFromEkEvent(calendarId: calendarId, ekEvent: ekEvent!)
                events.append(event)
            }
            
            self.encodeJsonAndFinish(codable: events, result: result)
        }, result: result)
    }
    
    private func createEventFromEkEvent(calendarId: String, ekEvent: EKEvent) -> Event {
        var attendees = [Attendee]()
        if ekEvent.attendees != nil {
            for ekParticipant in ekEvent.attendees! {
                let attendee = convertEkParticipantToAttendee(ekParticipant: ekParticipant)
                if attendee == nil {
                    continue
                }
                
                attendees.append(attendee!)
            }
        }
        
        var reminders = [Reminder]()
        if ekEvent.alarms != nil {
            for alarm in ekEvent.alarms! {
                reminders.append(Reminder(minutes: Int(-alarm.relativeOffset / 60)))
            }
        }

        let recurrenceRule = parseEKRecurrenceRules(ekEvent)
        let event = Event(
            eventId: ekEvent.eventIdentifier,
            calendarId: calendarId,
            title: ekEvent.title ?? "New Event",
            description: ekEvent.notes,
            start: Int64(ekEvent.startDate.millisecondsSinceEpoch),
            end: Int64(ekEvent.endDate.millisecondsSinceEpoch),
            allDay: ekEvent.isAllDay,
            attendees: attendees,
            location: ekEvent.location,
            url: ekEvent.url?.absoluteString,
            recurrenceRule: recurrenceRule,
            organizer: convertEkParticipantToAttendee(ekParticipant: ekEvent.organizer),
            reminders: reminders
        )
        return event
    }
    
    private func convertEkParticipantToAttendee(ekParticipant: EKParticipant?) -> Attendee? {
        if ekParticipant == nil || ekParticipant?.emailAddress == nil {
            return nil
        }

        let attendee = Attendee(name: ekParticipant!.name, emailAddress:  ekParticipant!.emailAddress!, role: ekParticipant!.participantRole.rawValue, attendanceStatus: ekParticipant!.participantStatus.rawValue)
        return attendee
    }

    private func parseEKRecurrenceRules(_ ekEvent: EKEvent) -> RecurrenceRule? {
        var recurrenceRule: RecurrenceRule?
        if ekEvent.hasRecurrenceRules {
            let ekRecurrenceRule = ekEvent.recurrenceRules![0]
            var frequency: Int
            switch ekRecurrenceRule.frequency {
            case EKRecurrenceFrequency.daily:
                frequency = 0
            case EKRecurrenceFrequency.weekly:
                frequency = 1
            case EKRecurrenceFrequency.monthly:
                frequency = 2
            case EKRecurrenceFrequency.yearly:
                frequency = 3
            default:
                frequency = 0
            }
            
            var totalOccurrences: Int?
            var endDate: Int64?
            if(ekRecurrenceRule.recurrenceEnd?.occurrenceCount != nil) {
                totalOccurrences = ekRecurrenceRule.recurrenceEnd?.occurrenceCount
            }
            
            let endDateMs = ekRecurrenceRule.recurrenceEnd?.endDate?.millisecondsSinceEpoch
            if(endDateMs != nil) {
                endDate = Int64(exactly: endDateMs!)
            }
            
            var weekOfMonth = ekRecurrenceRule.setPositions?.first?.intValue
            
            var daysOfWeek: [Int]?
            if ekRecurrenceRule.daysOfTheWeek != nil && !ekRecurrenceRule.daysOfTheWeek!.isEmpty {
                daysOfWeek = []
                for dayOfWeek in ekRecurrenceRule.daysOfTheWeek! {
                    daysOfWeek!.append(dayOfWeek.dayOfTheWeek.rawValue - 1)
                    
                    if weekOfMonth == nil {
                        weekOfMonth = dayOfWeek.weekNumber
                    }
                }
            }
            
            // For recurrence of nth day of nth month every year, no calendar parameters are given
            // So we need to explicitly set them from event start date
            var dayOfMonth = ekRecurrenceRule.daysOfTheMonth?.first?.intValue
            var monthOfYear = ekRecurrenceRule.monthsOfTheYear?.first?.intValue
            if (ekRecurrenceRule.frequency == EKRecurrenceFrequency.yearly
                && weekOfMonth == nil && dayOfMonth == nil && monthOfYear == nil) {
                let dateFormatter = DateFormatter()
                
                // Setting day of the month
                dateFormatter.dateFormat = "d"
                dayOfMonth = Int(dateFormatter.string(from: ekEvent.startDate))
                
                // Setting month of the year
                dateFormatter.dateFormat = "M"
                monthOfYear = Int(dateFormatter.string(from: ekEvent.startDate))
            }
            
            recurrenceRule = RecurrenceRule(
                recurrenceFrequency: frequency,
                totalOccurrences: totalOccurrences,
                interval: ekRecurrenceRule.interval,
                endDate: endDate,
                daysOfWeek: daysOfWeek,
                dayOfMonth: dayOfMonth,
                monthOfYear: monthOfYear,
                weekOfMonth: weekOfMonth)
        }
        
        return recurrenceRule
    }
    
    private func createEKRecurrenceRules(_ arguments: [String : AnyObject]) -> [EKRecurrenceRule]?{
        let recurrenceRuleArguments = arguments[recurrenceRuleArgument] as? Dictionary<String, AnyObject>
        if recurrenceRuleArguments == nil {
            return nil
        }
        
        let recurrenceFrequencyIndex = recurrenceRuleArguments![recurrenceFrequencyArgument] as? NSInteger
        let totalOccurrences = recurrenceRuleArguments![totalOccurrencesArgument] as? NSInteger
        let interval = recurrenceRuleArguments![intervalArgument] as? NSInteger
        var recurrenceInterval = 1
        let endDate = recurrenceRuleArguments![endDateArgument] as? NSNumber
        let namedFrequency = validFrequencyTypes[recurrenceFrequencyIndex!]
        
        var recurrenceEnd:EKRecurrenceEnd?
        if endDate != nil {
            recurrenceEnd = EKRecurrenceEnd(end: Date.init(timeIntervalSince1970: endDate!.doubleValue / 1000))
        } else if(totalOccurrences != nil && totalOccurrences! > 0) {
            recurrenceEnd = EKRecurrenceEnd(occurrenceCount: totalOccurrences!)
        }
        
        if interval != nil && interval! > 1 {
            recurrenceInterval = interval!
        }
                
        let daysOfWeekIndices = recurrenceRuleArguments![daysOfWeekArgument] as? [Int]
        var daysOfWeek : [EKRecurrenceDayOfWeek]?
        
        if daysOfWeekIndices != nil && !daysOfWeekIndices!.isEmpty {
            daysOfWeek = []
            for dayOfWeekIndex in daysOfWeekIndices! {
                // Append week number to BYDAY for yearly or monthly with 'last' week number
                if let weekOfMonth = recurrenceRuleArguments![weekOfMonthArgument] as? Int {
                    if namedFrequency == EKRecurrenceFrequency.yearly || weekOfMonth == -1 {
                        daysOfWeek!.append(EKRecurrenceDayOfWeek.init(
                            dayOfTheWeek: EKWeekday.init(rawValue: dayOfWeekIndex + 1)!,
                            weekNumber: weekOfMonth
                        ))
                    }
                }
                
                if daysOfWeek?.isEmpty == true {
                    daysOfWeek!.append(EKRecurrenceDayOfWeek.init(EKWeekday.init(rawValue: dayOfWeekIndex + 1)!))
                }
            }
        }
        
        var dayOfMonthArray : [NSNumber]?
        if let dayOfMonth = recurrenceRuleArguments![dayOfMonthArgument] as? Int {
            dayOfMonthArray = []
            dayOfMonthArray!.append(NSNumber(value: dayOfMonth))
        }
        
        var monthOfYearArray : [NSNumber]?
        if let monthOfYear = recurrenceRuleArguments![monthOfYearArgument] as? Int {
            monthOfYearArray = []
            monthOfYearArray!.append(NSNumber(value: monthOfYear))
        }
        
        // Append BYSETPOS only on monthly (but not last), yearly's week number (and last for monthly) appends to BYDAY
        var weekOfMonthArray : [NSNumber]?
        if namedFrequency == EKRecurrenceFrequency.monthly {
            if let weekOfMonth = recurrenceRuleArguments![weekOfMonthArgument] as? Int {
                if weekOfMonth != -1 {
                    weekOfMonthArray = []
                    weekOfMonthArray!.append(NSNumber(value: weekOfMonth))
                }
            }
        }
        
        return [EKRecurrenceRule(
            recurrenceWith: namedFrequency,
            interval: recurrenceInterval,
            daysOfTheWeek: daysOfWeek,
            daysOfTheMonth: dayOfMonthArray,
            monthsOfTheYear: monthOfYearArray,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: weekOfMonthArray,
            end: recurrenceEnd)]
    }
    
    private func setAttendees(_ arguments: [String : AnyObject], _ ekEvent: EKEvent?) {
        let attendeesArguments = arguments[attendeesArgument] as? [Dictionary<String, AnyObject>]
        if attendeesArguments == nil {
            return
        }
        
        var attendees = [EKParticipant]()
        for attendeeArguments in attendeesArguments! {
            let name = attendeeArguments[nameArgument] as! String
            let emailAddress = attendeeArguments[emailAddressArgument] as! String
            let role = attendeeArguments[roleArgument] as! Int
            
            if (ekEvent!.attendees != nil) {
                let existingAttendee = ekEvent!.attendees!.first { element in
                    return element.emailAddress == emailAddress
                }
                if existingAttendee != nil && ekEvent!.organizer?.emailAddress != existingAttendee?.emailAddress{
                    attendees.append(existingAttendee!)
                    continue
                }
            }
            
            let attendee = createParticipant(
                name: name,
                emailAddress: emailAddress,
                role: role)
            
            if (attendee == nil) {
                continue
            }
            
            attendees.append(attendee!)
        }
        
        ekEvent!.setValue(attendees, forKey: "attendees")
    }
    
    private func createReminders(_ arguments: [String : AnyObject]) -> [EKAlarm]?{
        let remindersArguments = arguments[remindersArgument] as? [Dictionary<String, AnyObject>]
        if remindersArguments == nil {
            return nil
        }
        
        var reminders = [EKAlarm]()
        for reminderArguments in remindersArguments! {
            let minutes = reminderArguments[minutesArgument] as! Int
            reminders.append(EKAlarm.init(relativeOffset: 60 * Double(-minutes)))
        }
        
        return reminders
    }
    
    private func createOrUpdateEvent(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        checkPermissionsThenExecute(permissionsGrantedAction: {
            let arguments = call.arguments as! Dictionary<String, AnyObject>
            let calendarId = arguments[calendarIdArgument] as! String
            let eventId = arguments[eventIdArgument] as? String
            let isAllDay = arguments[eventAllDayArgument] as! Bool
            let startDateMillisecondsSinceEpoch = arguments[eventStartDateArgument] as! NSNumber
            let endDateDateMillisecondsSinceEpoch = arguments[eventEndDateArgument] as! NSNumber
            let startDate = Date (timeIntervalSince1970: startDateMillisecondsSinceEpoch.doubleValue / 1000.0)
            let endDate = Date (timeIntervalSince1970: endDateDateMillisecondsSinceEpoch.doubleValue / 1000.0)
            let title = arguments[self.eventTitleArgument] as! String
            let description = arguments[self.eventDescriptionArgument] as? String
            let location = arguments[self.eventLocationArgument] as? String
            let url = arguments[self.eventURLArgument] as? String
            let followingInstances = arguments[followingInstancesArgument] as? Bool
            let ekCalendar = self.eventStore.calendar(withIdentifier: calendarId)
            if (ekCalendar == nil) {
                self.finishWithCalendarNotFoundError(result: result, calendarId: calendarId)
                return
            }
            
            if !(ekCalendar!.allowsContentModifications) {
                self.finishWithCalendarReadOnlyError(result: result, calendarId: calendarId)
                return
            }
            
            var ekEvent: EKEvent?
            if (eventId == nil) { // Create event
                ekEvent = EKEvent.init(eventStore: self.eventStore)
            } else {
                if (followingInstances == nil) { // Update all events
                    ekEvent = self.eventStore.event(withIdentifier: eventId!)
                }
                else { // Update event instance(s)
                    let predicate = self.eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
                    let foundEkEvents = self.eventStore.events(matching: predicate) as [EKEvent]?
                    
                    if foundEkEvents == nil || foundEkEvents?.count == 0 {
                        self.finishWithEventNotFoundError(result: result, eventId: eventId!)
                        return
                    }
                    
                    ekEvent = foundEkEvents!.first(where: {$0.eventIdentifier == eventId})
                }
                
                if (ekEvent == nil) {
                    self.finishWithEventNotFoundError(result: result, eventId: eventId!)
                    return
                }
            }
            
            ekEvent!.title = title
            ekEvent!.notes = description
            ekEvent!.isAllDay = isAllDay
            ekEvent!.startDate = startDate
            if (isAllDay) { ekEvent!.endDate = startDate }
            else { ekEvent!.endDate = endDate }
            ekEvent!.calendar = ekCalendar!
            ekEvent!.location = location

            // Create and add URL object only when if the input string is not empty or nil
            if let urlCheck = url, !urlCheck.isEmpty {
                let iosUrl = URL(string: url ?? "")
                ekEvent!.url = iosUrl
            }
            else {
                ekEvent!.url = nil
            }

            ekEvent!.recurrenceRules = createEKRecurrenceRules(arguments)
            setAttendees(arguments, ekEvent)
            ekEvent!.alarms = createReminders(arguments)

            do {
                if (followingInstances != nil && !followingInstances!) {
                    try self.eventStore.save(ekEvent!, span: .thisEvent)
                }
                else {
                    try self.eventStore.save(ekEvent!, span: .futureEvents)
                }
                result(ekEvent!.eventIdentifier)
            } catch {
                self.eventStore.reset()
                result(FlutterError(code: self.genericError, message: error.localizedDescription, details: nil))
            }
        }, result: result)
    }
    
    private func createParticipant(name: String, emailAddress: String, role: Int) -> EKParticipant? {
        let ekAttendeeClass: AnyClass? = NSClassFromString("EKAttendee")
        if let type = ekAttendeeClass as? NSObject.Type {
            let participant = type.init()
            participant.setValue(name, forKey: "displayName")
            participant.setValue(emailAddress, forKey: "emailAddress")
            participant.setValue(role, forKey: "participantRole")
            return participant as? EKParticipant
        }
        return nil
    }
    
    private func deleteEvent(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        checkPermissionsThenExecute(permissionsGrantedAction: {
            let arguments = call.arguments as! Dictionary<String, AnyObject>
            let calendarId = arguments[calendarIdArgument] as! String
            let eventId = arguments[eventIdArgument] as! String
            let startDateNumber = arguments[eventStartDateArgument] as? NSNumber
            let endDateNumber = arguments[eventEndDateArgument] as? NSNumber
            let followingInstances = arguments[followingInstancesArgument] as? Bool
            
            let ekCalendar = self.eventStore.calendar(withIdentifier: calendarId)
            if ekCalendar == nil {
                self.finishWithCalendarNotFoundError(result: result, calendarId: calendarId)
                return
            }
            
            if !(ekCalendar!.allowsContentModifications) {
                self.finishWithCalendarReadOnlyError(result: result, calendarId: calendarId)
                return
            }
            
            if (startDateNumber == nil && endDateNumber == nil && followingInstances == nil) {
                let ekEvent = self.eventStore.event(withIdentifier: eventId)
                if ekEvent == nil {
                    self.finishWithEventNotFoundError(result: result, eventId: eventId)
                    return
                }
                
                do {
                    try self.eventStore.remove(ekEvent!, span: .futureEvents)
                    result(true)
                } catch {
                    self.eventStore.reset()
                    result(FlutterError(code: self.genericError, message: error.localizedDescription, details: nil))
                }
            }
            else {
                let startDate = Date (timeIntervalSince1970: startDateNumber!.doubleValue / 1000.0)
                let endDate = Date (timeIntervalSince1970: endDateNumber!.doubleValue / 1000.0)
                                
                let predicate = self.eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
                let foundEkEvents = self.eventStore.events(matching: predicate) as [EKEvent]?
                
                if foundEkEvents == nil || foundEkEvents?.count == 0 {
                    self.finishWithEventNotFoundError(result: result, eventId: eventId)
                    return
                }
                
                let ekEvent = foundEkEvents!.first(where: {$0.eventIdentifier == eventId})
                
                do {
                    if (!followingInstances!) {
                        try self.eventStore.remove(ekEvent!, span: .thisEvent, commit: true)
                    }
                    else {
                        try self.eventStore.remove(ekEvent!, span: .futureEvents, commit: true)
                    }
                    
                    result(true)
                } catch {
                    self.eventStore.reset()
                    result(FlutterError(code: self.genericError, message: error.localizedDescription, details: nil))
                }
            }
        }, result: result)
    }
    
    private func finishWithUnauthorizedError(result: @escaping FlutterResult) {
        result(FlutterError(code:self.unauthorizedErrorCode, message: self.unauthorizedErrorMessage, details: nil))
    }
    
    private func finishWithCalendarNotFoundError(result: @escaping FlutterResult, calendarId: String) {
        let errorMessage = String(format: self.calendarNotFoundErrorMessageFormat, calendarId)
        result(FlutterError(code:self.notFoundErrorCode, message: errorMessage, details: nil))
    }
    
    private func finishWithCalendarReadOnlyError(result: @escaping FlutterResult, calendarId: String) {
        let errorMessage = String(format: self.calendarReadOnlyErrorMessageFormat, calendarId)
        result(FlutterError(code:self.notAllowed, message: errorMessage, details: nil))
    }
    
    private func finishWithEventNotFoundError(result: @escaping FlutterResult, eventId: String) {
        let errorMessage = String(format: self.eventNotFoundErrorMessageFormat, eventId)
        result(FlutterError(code:self.notFoundErrorCode, message: errorMessage, details: nil))
    }

    private func encodeJsonAndFinish<T: Codable>(codable: T, result: @escaping FlutterResult) {
        do {
            let jsonEncoder = JSONEncoder()
            let jsonData = try jsonEncoder.encode(codable)
            let jsonString = String(data: jsonData, encoding: .utf8)
            result(jsonString)
        } catch {
            result(FlutterError(code: genericError, message: error.localizedDescription, details: nil))
        }
    }
    
    private func checkPermissionsThenExecute(permissionsGrantedAction: () -> Void, result: @escaping FlutterResult) {
        if hasPermissions() {
            permissionsGrantedAction()
            return
        }
        self.finishWithUnauthorizedError(result: result)
    }
    
    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        if hasPermissions() {
            completion(true)
            return
        }
        eventStore.requestAccess(to: .event, completion: {
            (accessGranted: Bool, _: Error?) in
            completion(accessGranted)
        })
    }
    
    private func hasPermissions() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == EKAuthorizationStatus.authorized
    }
    
    private func requestPermissions(_ result: @escaping FlutterResult) {
        if hasPermissions()  {
            result(true)
        }
        eventStore.requestAccess(to: .event, completion: {
            (accessGranted: Bool, _: Error?) in
            result(accessGranted)
        })
    }
}

extension UIColor {

    func rgb() -> Int? {
        var fRed : CGFloat = 0
        var fGreen : CGFloat = 0
        var fBlue : CGFloat = 0
        var fAlpha: CGFloat = 0
        if self.getRed(&fRed, green: &fGreen, blue: &fBlue, alpha: &fAlpha) {
            let iRed = Int(fRed * 255.0)
            let iGreen = Int(fGreen * 255.0)
            let iBlue = Int(fBlue * 255.0)
            let iAlpha = Int(fAlpha * 255.0)

            //  (Bits 24-31 are alpha, 16-23 are red, 8-15 are green, 0-7 are blue).
            let rgb = (iAlpha << 24) + (iRed << 16) + (iGreen << 8) + iBlue
            return rgb
        } else {
            // Could not extract RGBA components:
            return nil
        }
    }
}

