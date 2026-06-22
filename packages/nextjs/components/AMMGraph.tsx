'use client';

import { ChartArea } from 'chart.js';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
} from 'chart.js';
import { Line } from 'react-chartjs-2';

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend
);

interface Props {
    E: number
    M: number
    pLo: number
    pHi: number
    ELo: number
    EHi: number
    MLo: number
    MHi: number
}

export default function AMMGraph(props: Props) {
    const E = props.E;
    const M = props.M;
    const pLo = props.pLo;
    const pHi = props.pHi;

    const pLoS = pLo ? pLo**0.5 : undefined;
    const pHiS = pHi ? pHi**0.5 : undefined;

    let Lv;
    if (pLo && pHi) {
        if (pLo === pHi) {
            Lv = E * pLo + M;
        } else {
            Lv = (E * pLoS + M / pHiS + Math.sqrt((E * pLoS - M / pHiS) ** 2.0 + 4.0 * M * E)) /
                (2.0 * (1.0 - pLoS / pHiS));
        }
    } else if (pLo) {
        Lv = (E * pLoS + Math.sqrt((E * pLoS) ** 2.0 + 4.0 * M * E)) / 2.0;
    } else if (pHi) {
        Lv = (M / pHiS + Math.sqrt((M / pHiS) ** 2.0 + 4.0 * M * E)) / 2.0;
    }else {
        Lv = Math.sqrt(E) * Math.sqrt(M);
    }

    const Ev = pHiS ? Lv / pHiS : 0;
    const Mv = pLoS ? Lv * pLoS : 0;

    const ELo = props.ELo || 0;
    const EHi = props.EHi || Mv == 0 ? 2 * E : Lv**2 / Mv - Ev;
    const MLo = props.MLo || 0;
    const MHi = props.MHi || Ev == 0 ? 2 * M : Lv**2 / Ev - Mv;

    const options = {
      responsive: true,
      aspectRatio: 1,
      maintainAspectRatio: true,
      interaction: {
          mode: '',
      },
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
    };

    const pricingCurve = (x: number) => {
        return Lv**2.0 / (x + Ev) - Mv;
    }

    let current = [0, 0];
    const xValues = [];
    const yValues = [];

    for (let x = ELo; x <= EHi; x += (EHi - ELo) / 1000.0) {
        let y = pricingCurve(x);
        if (y >= MLo && y <= MHi) {
            xValues.push(x);
            yValues.push(y);
        }
        if (Math.abs(E - x) < Math.abs(E - current[0])) {
            current[0] = x;
            current[1] = y;
        }
    }

    if (E < ELo || E > EHi || M < MLo || M > MHi) {
        current = [];
    }

    const data = {
      labels: xValues,
      datasets: [
        {
          type: 'scatter',
          data: xValues.map((x) => x == current[0] ? current[1] : undefined),
          borderColor: 'rgb(53, 162, 235)',
          backgroundColor: 'rgba(53, 162, 235, 1)',
          pointRadius: '4'
        },
        {
          data: yValues,
          borderColor: 'rgb(255, 99, 132)',
          backgroundColor: 'rgba(255, 99, 132, 1)',
          pointRadius: '1'
        },
      ],
    };

    return (
        <Line
            options={options}
            data={data}
        />
    );
}
