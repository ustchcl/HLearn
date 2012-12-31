{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE GADTs #-}

{-# LANGUAGE DataKinds #-}

module HLearn.Models.Distributions.KernelDensityEstimator
    ( KDEParams (..)
    , KDE (..)
    
    , Uniform (..)
    , Triangular (..)
    , Epanechnikov (..)
    , Quartic (..)
    , Triweight (..)
    , Tricube (..)
    , Gaussian (..)
    , Cosine (..)
    , KernelBox (..)
    )
    where
          
import HLearn.Algebra
import HLearn.Models.Distributions.Common

import qualified Data.Vector.Unboxed as VU

-------------------------------------------------------------------------------
--

data KDEParams prob = KDEParams
    { bandwidth :: prob
    , samplePoints :: VU.Vector prob -- ^ These data points must be sorted from smallest to largest
    , kernel :: KernelBox prob
    }
    deriving (Show,Eq)

data KDE' prob = KDE
    { params :: KDEParams prob
    , n :: Int
    , sampleVals :: VU.Vector prob
    }
    deriving (Show)

type KDE prob = RegSG2Group (KDE' prob)

-------------------------------------------------------------------------------
-- Algebra

instance (Eq prob, Num prob, VU.Unbox prob) => Semigroup (KDE' prob) where
    kde1 <> kde2 = if (params kde1) /= (params kde2)
        then error "KDE.(<>): different params"
        else kde1
            { n = (n kde1) + (n kde2)
            , sampleVals = VU.zipWith (+) (sampleVals kde1) (sampleVals kde2)
            }

instance (Eq prob, Num prob, VU.Unbox prob) => RegularSemigroup (KDE' prob) where
    inverse kde = kde
        { n = negate $ n kde
        , sampleVals = VU.map negate $ sampleVals kde
        }

-------------------------------------------------------------------------------
-- Training
    
instance (Eq prob, Num prob, VU.Unbox prob) => Model (KDEParams prob) (KDE prob) where
    getparams (SGJust kde) = params kde

-- instance DefaultModel MomentsParams (Moments prob n) where
--     defparams = MomentsParams

instance (Eq prob, Fractional prob, VU.Unbox prob) => HomTrainer (KDEParams prob) prob (KDE prob) where
    train1dp' params dp = SGJust $ KDE
        { params = params
        , n = 1
        , sampleVals = VU.map (\x -> k ((x-dp)/h)) (samplePoints params)
        }
        where
            k u = (evalkernel (kernel params) u)/h
            h   = bandwidth params

-------------------------------------------------------------------------------
-- Distribution
    
instance (Ord prob, Fractional prob, VU.Unbox prob) => Distribution (KDE prob) prob prob where
    pdf (SGJust kde) dp 
        | dp <= (samplePoints $ params kde) VU.! 0 = 0 -- (sampleVals kde) VU.! 0
        | dp >= (samplePoints $ params kde) VU.! l = 0 -- (sampleVals kde) VU.! l
        | otherwise = (y2-y1)/(x2-x1)*(dp-x1)+y1
        where
            index = binsearch (samplePoints $ params kde) dp
            x1 = (samplePoints $ params kde) VU.! (index-1)
            x2 = (samplePoints $ params kde) VU.! (index)
            y1 = ((sampleVals kde) VU.! (index-1)) / (fromIntegral $ n kde)
            y2 = ((sampleVals kde) VU.! (index  )) / (fromIntegral $ n kde)
            l = (VU.length $ samplePoints $ params kde)-1

binsearch :: (Ord a, VU.Unbox a) => VU.Vector a -> a -> Int
binsearch vec dp = go 0 (VU.length vec-1)
    where 
        go low high
            | low==high = low
            | dp <= (vec VU.! mid) = go low mid
            | dp >  (vec VU.! mid) = go (mid+1) high
            where 
                mid = floor $ (fromIntegral $ low+high)/2

-------------------------------------------------------------------------------
-- Kernels

-- | This list of kernels is take from wikipedia's: https://en.wikipedia.org/wiki/Uniform_kernel#Kernel_functions_in_common_use
class Kernel kernel num where
    evalkernel :: kernel -> num -> num

data KernelBox num where KernelBox :: (Kernel kernel num, Show kernel) => kernel -> KernelBox num
instance Kernel (KernelBox num) num where
    evalkernel (KernelBox k) p = evalkernel k p
instance Show (KernelBox num) where
    show (KernelBox k) = "KB "++show k
instance Eq (KernelBox num) where
    KernelBox k1 == KernelBox k2 = (show k1) == (show k2)
    
data Uniform = Uniform deriving (Read,Show)
instance (Fractional num, Ord num) => Kernel Uniform num where
    evalkernel Uniform u = if abs u < 1
        then 1/2
        else 0

data Triangular = Triangular deriving (Read,Show)
instance (Fractional num, Ord num) => Kernel Triangular num where
    evalkernel Triangular u = if abs u<1
        then 1-abs u
        else 0
        
data Epanechnikov = Epanechnikov deriving (Read,Show)
instance (Fractional num, Ord num) => Kernel Epanechnikov num where
    evalkernel Epanechnikov u = if abs u<1
        then (3/4)*(1-u^^2)
        else 0

data Quartic = Quartic deriving (Read,Show)
instance (Fractional num, Ord num) => Kernel Quartic num where
    evalkernel Quartic u = if abs u<1
        then (15/16)*(1-u^^2)^^2
        else 0
        
data Triweight = Triweight deriving (Read,Show)
instance (Fractional num, Ord num) => Kernel Triweight num where
    evalkernel Triweight u = if abs u<1
        then (35/32)*(1-u^^2)^^3
        else 0

data Tricube = Tricube deriving (Read,Show)
instance (Fractional num, Ord num) => Kernel Tricube num where
    evalkernel Tricube u = if abs u<1
        then (70/81)*(1-u^^3)^^3
        else 0
        
data Cosine = Cosine deriving (Read,Show)
instance (Floating num, Ord num) => Kernel Cosine num where
    evalkernel Cosine u = if abs u<1
        then (pi/4)*(cos $ (pi/2)*u)
        else 0
        
data Gaussian = Gaussian deriving (Read,Show)
instance (Floating num, Ord num) => Kernel Gaussian num where
    evalkernel Gaussian u = (1/(2*pi))*(exp $ (-1/2)*u^^2)