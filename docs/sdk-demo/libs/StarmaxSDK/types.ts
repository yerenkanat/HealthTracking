export type nullable<T> = T | null;
export interface BleFileSenderListener {
    onSuccess: () => void;
    onFailure: (status: number) => void;
    onProgress: (progress: number) => void;
    onSend: (buffer: ArrayBuffer) => void;
    onSendComplete: () => void;
}
export interface Dial {
    id: number;
    title: string;
    label_id: number;
    custom_id: number;
    pic_url: string;
    bin_url: string;
}
export enum NotifyType {
    CrcFailure = 0,
    Failure = 1,
    Pair = 2,
    Reset = 3,
    GetTime = 4,
    GetState = 5,
    SetState = 6,
    FindDevice = 7,
    GetStandAndExercise = 8,
    FindPhone = 9,
    CameraControl = 10,
    PhoneControl = 11,
    SetHeartRateAlarm = 12,
    SetPPGOpen = 13,
    GetBatteryV = 14,
    SetBtStatus = 15,
    Power = 16,
    BlueSysPair = 17,
    Version = 18,
    SetTime = 19,
    GetUserInfo = 20,
    SetUserInfo = 21,
    CustomDeviceInfo = 22,
    CustomDeviceDailyData = 23,
    CustomDeviceShakeOnOff = 24,
    SetMessagePushOpen = 25,
    GetMessagePushOpen = 26,
    GetGoals = 27,
    SetGoals = 28,
    GetBtStatus = 29,
    HealthDetail = 30,
    GetHealthIntervals = 31,
    SetHealthIntervals = 32,
    GetHealthOpen = 33,
    SetHealthOpen = 34,
    CloseDevice = 35,
    ShippingMode = 36,
    SetTimeOffset = 37,
    GetTimeOffset = 38,
    SetHeartRate = 39,
    GetHeartRate = 40,
    GetContact = 41,
    SetContact = 42,
    GetSos = 43,
    SetSos = 44,
    GetNotDisturb = 45,
    SetNotDisturb = 46,
    GetClocks = 47,
    SetClocks = 48,
    GetLongSit = 49,
    SetLongSit = 50,
    GetDrinkWater = 51,
    SetDrinkWater = 52,
    SendMessage = 53,
    SetWeather = 54,
    GetWeatherSeven = 55,
    SetWeatherSeven = 56,
    MusicControl = 57,
    GetEventReminder = 58,
    SetEventReminder = 59,
    GetSportMode = 60,
    SetSportMode = 61,
    GetApps = 62,
    SetApps = 63,
    GetWorldClocks = 64,
    SetWorldClocks = 65,
    GetPassword = 66,
    SetPassword = 67,
    GetFemaleHealth = 68,
    SetFemaleHealth = 69,
    HealthMeasure = 70,
    SportHistory = 71,
    StepHistory = 72,
    HeartRateHistory = 73,
    BloodPressureHistory = 74,
    BloodOxygenHistory = 75,
    PressureHistory = 76,
    MetHistory = 77,
    TempHistory = 78,
    Mai = 79,
    BloodSugarHistory = 80,
    SleepHistory = 81,
    RespirationRateHistory = 82,
    ExerciseHistory = 83,
    ValidHistoryDates = 84,
    SendFileInfo = 85,
    SendFile = 86,
    DialInfo = 87,
    SwitchDial = 88,
    Log = 89,
    GetRealTimeOpen = 90,
    SetRealTimeOpen = 91,
    RealTimeData = 92,
    RealTimeMeasure = 93,
    WristDetachment = 94,
    Diff = 95,
    MaiHistory = 96,
    OriginSleepHistory = 97,
    GetCustomOnOff = 98,
    SetCustomOnOff = 99,
    HealthCalibration = 100,
    HealthCalibrationStatus = 101,
    GetSummerWorldClock = 102,
    SetSummerWorldClock = 103,
    DebugInfo = 104,
    ClearLogo = 105,
    NfcCardInfo = 106,
    NfcCardStatus = 107,
    NfcM1 = 108,
    DisplayMode = 109,
    SportSyncFromDevice = 110,
    SportSyncToDevice = 111,
    SupportLanguages = 112,
    ShipMode = 113,
    SportModeOnOff = 114,
    GetCustomBroadcast = 115,
    SetCustomBroadcast = 116,
    GetSleepClock = 117,
    SetSleepClock = 118,
    GetDateFormat = 119,
    SetDateFormat = 120,
    ShakeHeadHistory = 121,
    Unpair = 122,
    UnpairNotify = 123,
    UnitTest = 124,
    GetGoalsDayAndNight = 125,
    SetGoalsDayAndNight = 126,
    GetGoalsNotUp = 127,
    SetGoalsNotUp = 128,
    GetCustomHealthGoals = 129,
    SetCustomHealthGoals = 130,
    GetCustomHealthGoalTasks = 131,
    SetCustomHealthGoalTasks = 132,
    CustomHealthGoalsHistory = 133,
    GoalsDayAndNightHistory = 134,
    QuickBatteryMode = 135,
    SendFileV2 = 136,
    GetFileV2 = 137,
    GetFileV2Content = 138,
    GetFileV2Complete = 139
}
export enum HealthMeasureType {
    Pressure = 102,
    HeartRate = 99
}
export enum HistoryType {
    Sport = 0,
    Step = 1,
    HeartRate = 2,
    BloodPressure = 3,
    BloodOxygen = 4,
    Pressure = 5,
    Met = 6,
    Temp = 7,
    Mai = 8,
    BloodSugar = 9,
    Sleep = 10,
    RespirationRate = 11,
    Exercise = 12,
    ShakeHead = 13,
    CustomHealthGoals = 14,
    GoalsDayAndNight = 15
}
export enum CameraControlType {
    CameraIn = 1,
    CameraExit = 2,
    TakePhoto = 3
}
export enum MessageType {
    Phone = 1,
    Sms = 2,
    Mail = 3,
    Twitter = 4,
    Facebook = 5,
    WhatsApp = 6,
    Line = 7,
    Skype = 8,
    QQ = 9,
    Wechat = 10,
    Instagram = 11,
    Linkedin = 12,
    Messenger = 13,
    VK = 14,
    Viber = 15,
    Telegram = 16,
    KakaoTalk = 17,
    Other = 18,
    Threads = 19,
    GroupMe = 20,
    WHOO = 21,
    Discord = 22,
    Signal = 23,
    DingDing = 24,
    WxWork = 25,
    Feishu = 26
}
export enum CallControlType {
    Answer = 1,
    HangUp = 2,
    Incoming = 3,
    Exit = 4
}
export interface LocationData {
    longitude: number;
    latitude: number;
}
export interface sportSyncToDeviceRequest {
    sportType: number;
    sportStatus: number;
    sportDistance: number;
    speed: number;
    locationList: Array<LocationData>;
}
export enum HealthIntervalType {
    HeartRate = 1,
    BloodOxygen = 2,
    Temp = 3,
    Hrv = 4,
    BloodSugar = 5,
    BloodPressure = 6,
    RespiratoryRate = 7
}
export interface getX04HealthIntervalsResponse {
    cmdType: number;
    type: NotifyType;
    status: number;
    healthIntervalsData: HealthInterval[];
}
export interface sendUiRequest {
    offset: number;
    version: string;
    fileSize: number;
}
export interface sendDialRequest {
    dialId: number;
    color: number;
    align: number;
    fileSize: number;
}
export interface HealthInterval {
    healthType: HealthIntervalType;
    measureInterval: number;
    storeInterval: number;
}
export interface SummerWorldClock {
    cityId: number;
    startMonth: number;
    startWeek: number;
    endMonth: number;
    endWeek: number;
    timeOffset: number;
}
export interface SetRealTimeOpenRequest {
    gsensor: boolean;
    steps: boolean;
    heartRate: boolean;
    bloodPressure: boolean;
    bloodOxygen: boolean;
    temp: boolean;
    bloodSugar: boolean;
    hasSugar: boolean;
}
export type EventReminder = {
    year: number;
    month: number;
    day: number;
    hour: number;
    minute: number;
    content: string;
    repeats: Array<number>;
    remindType: number;
    repeatType: number;
    reminderIndex?: number;
};
export type WeatherDay = {
    temp: number;
    maxTemp: number;
    minTemp: number;
    windSpeed: number;
    dampness: number;
    seeing: number;
    uv: number;
    airQuality: number;
    type: number;
    sunriseHour?: number;
    sunriseMinute?: number;
    sunsetHour?: number;
    sunsetMinute?: number;
    moonriseHour?: number;
    moonriseMinute?: number;
    moonsetHour?: number;
    moonsetMinute?: number;
};
export type WeatherDaySeven = {
    temp: number;
    maxTemp: number;
    minTemp: number;
    windSpeed: number;
    dampness: number;
    seeing: number;
    uv: number;
    airQuality: number;
    type: number;
    sunriseHour: number;
    sunriseMinute: number;
    sunsetHour: number;
    sunsetMinute: number;
    moonriseHour: number;
    moonriseMinute: number;
    moonsetHour: number;
    moonsetMinute: number;
};
export type setFemaleHealthRequest = {
    numberOfDays: number;
    lastPeriodYear: number;
    lastPeriodMonth: number;
    lastPeriodDay: number;
    cycleDays: number;
    remindOnOff?: boolean;
};
export type getFemaleHealthResponse = setFemaleHealthRequest & basicResponse;
export interface RequestOptions {
    cmd: number;
    dataLen?: number;
    data: number[];
}
export interface ExtendRequestOptions {
    cmd: number;
    data: number[];
    type: number;
}
export interface setPasswordRequest {
    password: string;
    isOpen: boolean;
}
export interface musicControlRequest {
    playState: number;
    volPercent: number;
    ratePercent: number;
    musicTitle: string;
    lyric: string;
}
export interface getEventReminderResponse {
    type: NotifyType;
    status: number;
    eventReminders: Array<EventReminder>;
}
export interface setWeatherSevenRequest {
    cityName: string;
    weatherDays: Array<WeatherDaySeven>;
}
export interface getSportHistoryResponse {
    type: NotifyType;
    status: number;
    sportLength: number;
    currentSportId: number;
    currentSportDataLength: number;
    year: number;
    month: number;
    day: number;
    hour: number;
    minute: number;
    second: number;
    sportSeconds: number;
    sportType: number;
    steps: number;
    distance: number;
    speed: number;
    calorie: number;
    paceTime: number;
    stepFrequency: number;
    heartRateAvg: number;
    heartRateLength: number;
    heartRateList: number[];
    locationLength: number;
    locations: {
        lat: number;
        lng: number;
    }[];
}
export type MessagePushSwitchRequest = {
    mainSwitch: boolean;
    switches: {
        phone?: boolean;
        sms?: boolean;
        mail?: boolean;
        twitter?: boolean;
        facebook?: boolean;
        whatsapp?: boolean;
        line?: boolean;
        skype?: boolean;
        qq?: boolean;
        wechat?: boolean;
        instagram?: boolean;
        linkedin?: boolean;
        messenger?: boolean;
        vk?: boolean;
        viber?: boolean;
        telegram?: boolean;
        kakaoTalk?: boolean;
        other?: boolean;
        threads?: boolean;
        groupme?: boolean;
        whoo?: boolean;
        discord?: boolean;
        signal?: boolean;
        dingtalk?: boolean;
        wecom?: boolean;
        feishu?: boolean;
    };
};
export type MessagePushSwitchResponse = basicResponse & MessagePushSwitchRequest;
export interface sendMessageRequest {
    content: string;
    title: string;
    messageType: MessageType;
}
export type SetSleepClocksRequest = {
    fallAsleepHour: number;
    fallAsleepMinute: number;
    fallAsleepOnOff: boolean;
    getUpHour: number;
    getUpMinute: number;
    getUpOnOff: boolean;
    onOff: boolean;
    repeats: Array<number>;
    reminderAdvanceMinute: number;
};
export type GetSleepClockResponse = basicResponse & SetSleepClocksRequest;
export interface healthMeasureRequest {
    healthType: HealthMeasureType;
    onOff: boolean;
}
export interface syncTime {
    year: number;
    month: number;
    day: number;
}
export interface SportSyncFromDeviceResponse {
    status: number;
    type: NotifyType;
    sportType: number;
    sportStatus: number;
    steps: number;
    calorie: number;
    paceTime: number;
    cadence: number;
    heartRate: number;
    sportSeconds: number;
}
export interface healthCalibrationRequest {
    calibrateType: number;
    cmd: number;
    year: number;
    month: number;
    day: number;
    value: Array<CalibrationValue>;
}
export type CalibrationValue = {
    hour: number;
    minute: number;
    data1: number;
    data2: number;
};
export interface WristDetachmentResponse {
    type: NotifyType;
    status: number;
    isWear: boolean;
}
export type basicResponse = {
    type: NotifyType;
    status: number;
};
export type basicResponseWithoutProps = {
    type: NotifyType;
    data: {
        status: number;
    };
};
export interface GetWorldClocksResponse {
    type: NotifyType;
    status: number;
    citys: number[];
}
export interface GetWeatherSevenResponse {
    type: NotifyType;
    status: number;
    year: number;
    month: number;
    day: number;
    hour: number;
    city: string;
    minute: number;
    days: Array<WeatherDaySeven>;
}
export interface getAppsResponse {
    type: NotifyType;
    status: number;
    apps: Array<number>;
}
export interface getTimeResponse {
    type: NotifyType;
    status: number;
    year: number;
    month: number;
    day: number;
    hour: number;
    minute: number;
    second: number;
    timeOffset: number;
}
export interface PairResponse {
    type: NotifyType;
    status: number;
    pairStatus?: number;
}
export interface setUserInfoRequest {
    sex: number;
    age: number;
    height: number;
    weight: number;
}
export interface setUserInfoGts10Request {
    sex: number;
    age: number;
    height: number;
    weight: number;
    wearRightHand: boolean;
}
export interface getBtStatusResponse {
    type: NotifyType;
    status: number;
    isConnect: boolean;
}
export interface getStandAndExerciseResponse {
    status: number;
    type: NotifyType;
    stand_time: number;
    exercise_time: number;
}
export interface phoneControlRequest {
    value: string;
    isNumber: boolean;
    callControlType: CallControlType;
}
export interface PhoneControlResponse {
    type: NotifyType;
    status: number;
    value: string;
    callControlType: CallControlType;
}
export interface setUserInfoGts10Request {
    sex: number;
    age: number;
    height: number;
    weight: number;
    wearRightHand: boolean;
}
export interface setStateRequest {
    timeFormat: number;
    unitFormat: number;
    tempFormat: number;
    language: number;
    backlighting: number;
    screen: number;
    wristUp: boolean;
}
export interface getStateResponse {
    type: NotifyType;
    status: number;
    timeFormat: number;
    unitFormat: number;
    tempFormat: number;
    language: number;
    backlighting: number;
    screen: number;
    wristUp: boolean;
}
export interface setGoalsRequest {
    steps: number;
    distance: number;
    heat: number;
}
export interface getGoalsResponse {
    type: NotifyType;
    status: number;
    steps: number;
    distance: number;
    heat: number;
}
export interface getHeartRateControlResponse {
    startHour: number;
    startMinute: number;
    endHour: number;
    endMinute: number;
    period: number;
    alarmThreshold: number;
    oxygenPeriod: number;
    type: NotifyType;
    status: number;
}
export type Contact = {
    number: string;
    name: string;
};
export interface getContactResponse {
    type: NotifyType;
    status: number;
    contacts: Contact[];
}
export interface getSosResponse {
    type: NotifyType;
    status: number;
    sos: Contact[];
}
export type Clock = {
    hour: number;
    minute: number;
    onOff: boolean;
    repeats: number[];
    clockType?: number;
};
export interface getClocksResponse {
    type: NotifyType;
    status: number;
    clockList: Clock[];
}
export interface getSportModes {
    type: NotifyType;
    status: number;
    modes: number[];
}
export interface setHeartRateControlRequest {
    startHour: number;
    startMinute: number;
    endHour: number;
    endMinute: number;
    period: number;
    alarmThreshold: number;
}
export interface setHeartRateControlWithOxygenRequest {
    startHour: number;
    startMinute: number;
    endHour: number;
    endMinute: number;
    period: number;
    alarmThreshold: number;
    oxygenPeriod: number;
}
export interface findPhoneResponse {
    type: NotifyType;
    status: number;
    isFind: boolean;
}
export interface getPowerResponse {
    type: NotifyType;
    status: number;
    power: number;
    isCharge: boolean;
}
export type dateType = {
    year: number;
    month: number;
    day: number;
};
export interface getValidHistoryDatesResponse {
    type: NotifyType;
    status: number;
    validHistoryDates: dateType[];
}
export interface ExerciseData {
    hour: number;
    minute: number;
    intensity: number;
}
export interface StandData {
    hour: number;
    minute: number;
    standCount: number;
}
export interface respirationRate {
    hour: number;
    minute: number;
    respirationRate: number;
}
export interface respirationRateHistory {
    status: number;
    type: NotifyType;
    interval: number;
    year: number;
    month: number;
    day: number;
    dataLength: number;
    respirationRateList: Array<respirationRate>;
}
export interface ShakeHead {
    hour: number;
    minute: number;
    shakeHeadCount: number;
}
export interface shakeHeadHistoryResponse {
    type: NotifyType;
    status: number;
    interval: number;
    year: number;
    month: number;
    day: number;
    dataLength: number;
    shakeHeadData: Array<ShakeHead>;
}
export interface sleepData {
    hour: number;
    minute: number;
    status: number;
}
export interface sleepHistoryResponse {
    type: NotifyType;
    status: number;
    interval: number;
    year: number;
    month: number;
    day: number;
    dataLength: number;
    sleepDataList: Array<sleepData>;
}
export interface bloodSugarData {
    hour: number;
    minute: number;
    bloodSugar: number;
}
export interface bloodSugarHistoryResponse {
    type: NotifyType;
    status: number;
    interval: number;
    year: number;
    month: number;
    day: number;
    dataLength: number;
    bloodSugarList: Array<bloodSugarData>;
}
export interface maiHistoryResponse {
    type: NotifyType;
    status: number;
    interval: number;
    year: number;
    month: number;
    day: number;
    dataLength: number;
    maiList: Array<number>;
}
export interface tempData {
    hour: number;
    minute: number;
    temp: number;
}
export interface tempHistoryResponse {
    type: NotifyType;
    status: number;
    interval: number;
    year: number;
    month: number;
    day: number;
    dataLength: number;
    tempList: Array<tempData>;
}
export interface metHistoryResponse {
    type: NotifyType;
    status: number;
    interval: number;
    year: number;
    month: number;
    day: number;
    dataLength: number;
    metList: Array<number>;
}
export interface pressureData {
    hour: number;
    minute: number;
    pressure: number;
}
export interface pressureHistoryResponse {
    type: NotifyType;
    status: number;
    interval: number;
    year: number;
    month: number;
    day: number;
    dataLength: number;
    pressureList: Array<pressureData>;
}
export interface bloodOxygenData {
    hour: number;
    minute: number;
    bloodOxygen: number;
}
export interface bloodOxygenHistoryResponse {
    type: NotifyType;
    status: number;
    interval: number;
    year: number;
    month: number;
    day: number;
    dataLength: number;
    bloodOxygenList: Array<bloodOxygenData>;
}
export interface bloodPressureData {
    hour: number;
    minute: number;
    ss: number;
    fz: number;
}
export interface bloodPressureHistoryResponse {
    status: number;
    type: NotifyType;
    interval: number;
    year: number;
    month: number;
    day: number;
    dataLength: number;
    bloodPressureList: Array<bloodPressureData>;
}
export interface stepsData {
    hour: number;
    minute: number;
    dataType: number;
    steps: number;
    calorie: number;
    distance: number;
}
export interface sleepsData {
    hour: number;
    minute: number;
    dataType: number;
    sleepStatus: number;
}
export interface stepHistoryResponse {
    type: NotifyType;
    status: number;
    interval: number;
    year: number;
    month: number;
    day: number;
    dataLength: number;
    stepsList: Array<stepsData>;
    sleepsList: Array<sleepsData>;
}
export interface heartRateData {
    hour: number;
    minute: number;
    heartRateValue: number;
}
export interface heartRateHistoryResponse {
    type: NotifyType;
    status: number;
    interval: number;
    year: number;
    month: number;
    day: number;
    dataLength: number;
    heartRateList: Array<heartRateData>;
}
export interface getExerciseHistoryResponse {
    type: NotifyType;
    status: number;
    interval: number;
    year: number;
    month: number;
    day: number;
    dataLength: number;
    exerciseDataList: Array<ExerciseData>;
    standDataList: Array<StandData>;
}
export interface getVersionResponse {
    type: NotifyType;
    status: number;
    version: string;
    uiVersion: string;
    bufferSize: number;
    lcdWidth: number;
    lcdHeight: number;
    screenType: number;
    model: string;
    uiForceUpdate: boolean;
    uiSupportDifferentialUpgrade?: boolean;
    supportSugar?: boolean;
    protocolVersion?: string;
    supportNewSleepAlgorithm?: boolean;
    newSleepShowWay?: number;
    supportSleepNotice?: boolean;
    supportUnbind?: boolean;
}
export interface cameraControlResponse {
    type: NotifyType;
    status: number;
    controlType: number;
}
export interface getUserInfoResponse {
    type: NotifyType;
    status: number;
    sex: string;
    age: number;
    height: number;
    weight: number;
    wearRightHand?: boolean;
}
export interface setHealthOpenRequest {
    heartRate: boolean;
    bloodPressure: boolean;
    bloodOxygen: boolean;
    pressure: boolean;
    temp: boolean;
    bloodSugar: boolean;
    breatheRate: boolean;
}
export interface getBatteryVResponse {
    type: NotifyType;
    status: number;
    battery: number;
    batteryV: string;
}
export interface getHealthDetailResponse {
    type: NotifyType;
    status: number;
    totalSteps: number;
    totalHeat: number;
    totalDistance: number;
    totalSleep: number;
    totalDeepSleep: number;
    totalLightSleep: number;
    currentHeartRate: number;
    currentFz: number;
    currentSs: number;
    currentBloodOxygen: number;
    currentPressure: number;
    currentMet: number;
    currentMai: number;
    currentTemp: number;
    currentBloodSugar: number;
    isWear: number;
    breatheRate: number;
    shakeHead: number;
}
export interface getHealthOpenResponse {
    type: NotifyType;
    status: number;
    heartRate: boolean;
    bloodPressure: boolean;
    bloodOxygen: boolean;
    pressure: boolean;
    temp: boolean;
    bloodSugar: boolean;
    breatheRate: boolean;
}
export type setNotDisturbRequest = {
    onOff: boolean;
    allDayOnOff: boolean;
    startHour: number;
    startMinute: number;
    endHour: number;
    endMinute: number;
};
export type getNotDisturbResponse = setNotDisturbRequest & basicResponse;
export type setLongSitRequest = {
    onOff: boolean;
    startHour: number;
    startMinute: number;
    endHour: number;
    endMinute: number;
    interval: number;
};
export type getLongSitResponse = setLongSitRequest & basicResponse;
export type setDrinkWaterRequest = {
    onOff: boolean;
    startHour: number;
    startMinute: number;
    endHour: number;
    endMinute: number;
    interval: number;
};
export type getDrinkWaterResponse = setDrinkWaterRequest & basicResponse;
