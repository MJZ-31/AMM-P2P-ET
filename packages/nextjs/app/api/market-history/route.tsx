import { NextResponse, NextRequest } from 'next/server';

import readMarketHistory from '~~/hooks/mysql/readMarketHistory';

export async function GET(request: NextRequest) {
    try {
        return NextResponse.json(await readMarketHistory(undefined, undefined));
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
