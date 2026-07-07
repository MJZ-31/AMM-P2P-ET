'use client';

import {
  Chart as ChartJS,
  CategoryScale,
  Legend,
  LinearScale,
  PointElement,
  LineElement,
  TimeScale,
  Title,
  Tooltip,
  Filler
} from 'chart.js';
import { Line } from 'react-chartjs-2';
import 'chartjs-adapter-date-fns';

import { useEffect, useState } from 'react';

import readMarketHistory from '~~/hooks/mysql/readMarketHistory'

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  TimeScale,
  Title,
  Tooltip,
  Legend,
  Filler
);

interface Props {
    startTimestamp: Date,
    endTimestamp: Date
    poolPriceMin: number
    poolPriceMax: number
}

export default function HistoryGraph(props: Props) {
    const [marketHistory, setMarketHistory] = useState([]);

    useEffect(() => {
        (async () => {
            setMarketHistory(await readMarketHistory(props.startTimestamp, props.endTimestamp));
        })()
    }, [props])

    const options = {
      responsive: true,
      aspectRatio: 1.5,
      layout: {
          autoPadding: false,
      },
      plugins: {
        legend: {
          display: false,
        },
        title: {
          display: false,
        },
      },
      scales: {
          xAxis: {
              type: "time",
          },
          y: {
              min: props.poolPriceMin,
              max: props.poolPriceMax,
          }
      },
    };

    const data = {
      datasets: [
        {
          data: marketHistory
              .map((row) => { return { "x": row.timestamp, "y": Number(row.pool_price) } }),
          borderColor: 'rgb(53, 162, 235)',
          backgroundColor: 'rgba(53, 162, 235)',
          pointRadius: '1'
        },
        {
          data: [
              { "x": new Date(), "y": props.poolPriceMin },
              { "x": new Date(), "y": props.poolPriceMax }
          ],
          pointRadius: '0'
        }
      ],
    };

    return (
        <Line
            options={options}
            data={data}
        />
    );
}
