import { EventReminder } from "./types";
export declare const CRC16Table: number[];
export declare function calcCrc(cData: Array<number>, cLength: number): string;
export declare function ab2hex(buffer: ArrayBuffer): string;
export declare function getUtcOffset(date: Date): number;
export declare function hexToAscii(hexString: string): string;
export declare function stringToUTF8Array(str: string): number[];
/**
 * 将字节数组按 Unicode (UTF-16 LE) 解码为字符串
 * @param {number[]} bytes - 字节数组
 * @returns {string} 解码后的字符串
 */
export declare function unicodeBytesToString(bytes: number[]): string;
export declare function utf8BytesToString(bytes: number[]): string;
export declare function stringToUTF16Array(str: string): number[];
export declare function stringToUtf16LEBytes(str: string): Uint8Array;
export declare function decodeUTF16LE(bytes: Uint8Array): string;
export declare function getTimeOffsetBytes(offsetMinutes: number): Uint8Array;
export declare function copyToArray(b: number[], size: number): any[];
export declare function parsePhone(input: string): string;
export declare function toBle(reminder: EventReminder): number[];
export declare function int2byte(value: number, length?: number): number[];
export declare function int2byteLittleEndian(value: number, length: number): number[];
export declare function doubleToBytes(value: number): number[];
export declare function byteArray2Sum(bytes: number[]): number;
export declare function byteArray2SumLong(bytes: number[]): bigint;
export declare function bytesToDouble(value: any): number;
export declare function splitArrayBuffer(buffer: ArrayBuffer): Uint8Array[];
