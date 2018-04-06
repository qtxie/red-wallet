Red [
	Title:	"Driver for Ledger Nano S"
	Author: "Xie Qingtian"
	File: 	%ledger.red
	Tabs: 	4
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/red/red/blob/master/BSL-License.txt
	}
]

#include %hidapi.red
#include %rlp.red

to-bin8: func [v [integer! char!]][
	to binary! to char! 256 + v and 255
]

to-bin16: func [v [integer! char!]][	;-- big-endian encoding
	skip to-binary to-integer v 2
]

to-bin32: func [v [integer! char!]][	;-- big-endian encoding
	to-binary to-integer v
]

to-int16: func [b [binary!]][
	to-integer copy/part b 2
]

ledger: context [

	DEFAULT_CHANNEL:	0101h
	TAG_APDU:			05h
	PACKET_SIZE:		65
	MAX_APDU_SIZE:		260

	dongle: none
	buffer:		make binary! MAX_APDU_SIZE
	data-frame: make binary! PACKET_SIZE

	connect: func [][
		unless dongle [
			dongle: hid/open 2C97h 1	;-- vendor ID (2C97h) and product ID (01h) for the Nano S
		]
		dongle
	]

	read-apdu: func [
		timeout [integer!]				;-- seconds
		/local idx total msg-len data
	][
		idx: 0
		clear buffer
		until [
			if none? hid/read dongle clear data-frame timeout * 1000 [
				throw "Read Error"
			]

			data: data-frame

			;-- sanity check the frame
			if DEFAULT_CHANNEL <> to-int16 data [
				throw "APDU Wrong Channel"
			]
			if TAG_APDU <> data/3 [
				throw "APDU Wrong Tag"
			]
			if idx <> to-int16 skip data 3 [
				throw "APDU Wrong Sequence"
			]

			;-- extract the message
			data: skip data 5
			if zero? idx [
				total: to-int16 data
				data: skip data 2
			]
			idx: idx + 1

			msg-len: min total length? data

			append/part buffer data msg-len
			total: total - msg-len
			zero? total
		]
		buffer
	]

	write-apdu: func [data [binary!] /local idx limit][
		idx: 0
		while [not empty? data][
			clear data-frame
			append data-frame reduce [	;-- header
				0
				to-bin16 DEFAULT_CHANNEL
				TAG_APDU
				to-bin16 idx
			]

			if zero? idx [				;-- first packet's header includes a two-byte length
				append data-frame to-bin16 length? data
			]
			idx: idx + 1

			limit: PACKET_SIZE - length? data-frame
			append/part data-frame data limit
			;if PACKET_SIZE <> length? data-frame [
			;	append/dup data-frame 0 PACKET_SIZE - length? data-frame
			;]
			data: skip data limit
			hid/write dongle data-frame
		]
	]

	get-address: func [idx [integer!] /local data pub-key-len addr-len][
		data: make binary! 20
		append data reduce [
			E0h
			02h
			0
			0
			4 * 4 + 1
			4
			to-bin32 8000002Ch
			to-bin32 8000003Ch
			to-bin32 80000000h
			to-bin32 idx
		]
		write-apdu data
		data: read-apdu 10

		if 40 < length? data [
			;-- parse reply data
			pub-key-len: to-integer data/1
			addr-len: to-integer pick skip data pub-key-len + 1 1
			rejoin ["0x" to-string copy/part skip data pub-key-len + 2 addr-len]
		]
	]

	sign-eth-tx: func [addr-idx [integer!] tx [block!] /local data max-sz sz signed][
		;-- tx: [nonce, gasprice, startgas, to, value, data]
		tx-bin: rlp/encode tx
		chunk: make binary! 200
		while [not empty? tx-bin][
			clear chunk
			insert/dup chunk 0 5
			max-sz: either head? tx-bin [133][150]
			sz: min max-sz length? tx-bin
			chunk/1: E0h
			chunk/2: 04h
			chunk/3: either head? tx-bin [0][80h]
			chunk/4: 0
			chunk/5: either head? tx-bin [sz + 17][sz]
			if head? tx-bin [
				append chunk reduce [
					4
					to-bin32 8000002Ch
					to-bin32 8000003Ch
					to-bin32 80000000h
					to-bin32 addr-idx
				]
			]
			append/part chunk tx-bin sz
			write-apdu chunk
			signed: read-apdu 300
			?? signed
			tx-bin: skip tx-bin sz
		]
		signed
	]

	close: does [hid/close dongle]
]

;ledger/connect

;probe ledger/get-address 0

;ledger/close
