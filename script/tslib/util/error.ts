import { ErrorDecoder } from 'ethers-decode-error';
import * as tt from '../typechain-types';

export const newErrorDecoder = () => {
    return ErrorDecoder.create([
        tt.Merge_custom_errors__factory.createInterface(),
    ]);
}
