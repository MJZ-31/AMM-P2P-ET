import { NextResponse, NextRequest } from 'next/server';

import readMarketHistory from '~~/hooks/mysql/readMarketHistory';

export async function GET(
    request: NextRequest,
    { params }: { params: Promise<{ startTime: string, endTime: string }> }
) {
    try {
        const { startTime, endTime } = await params;
        const start: Date = new Date(startTime);
        const end: Date = new Date(endTime);
        return NextResponse.json(await readMarketHistory(start, end));
    } catch (err) {
        const msg = (err as Error).message;
        console.log('ERROR: API -', msg);
        const response = {
            error: msg,
            returnedStatus: 200
        };
        return NextResponse.json(response, { status: 200 });
    }
}
